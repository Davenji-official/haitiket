-- 0014: portefeuille interne HAITIKET et opérations idempotentes.
-- Les crédits/débits ne sont jamais accessibles en écriture depuis le client.
create table if not exists public.wallet_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  currency text not null check (currency in ('HTG','USD')),
  created_at timestamptz not null default now(),
  unique(user_id,currency)
);
create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.wallet_accounts(id),
  user_id uuid not null references auth.users(id),
  reference text not null unique,
  kind text not null check(kind in ('topup','purchase','seller_credit','courier_credit','subscription_fee','withdrawal','refund','adjustment')),
  status text not null default 'pending' check(status in ('pending','processing','successful','failed','reversed','review')),
  amount_minor bigint not null check(amount_minor > 0),
  fee_minor bigint not null default 0 check(fee_minor >= 0),
  currency text not null check(currency in ('HTG','USD')),
  provider text not null default 'internal',
  provider_transaction_id text,
  recipient_phone text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists wallet_transactions_user_created_idx on public.wallet_transactions(user_id,created_at desc);
create unique index if not exists wallet_provider_tx_unique on public.wallet_transactions(provider,provider_transaction_id) where provider_transaction_id is not null;
alter table public.wallet_accounts enable row level security;
alter table public.wallet_transactions enable row level security;
drop policy if exists wallet_account_self_read on public.wallet_accounts;
create policy wallet_account_self_read on public.wallet_accounts for select to authenticated using(user_id=auth.uid());
drop policy if exists wallet_tx_self_read on public.wallet_transactions;
create policy wallet_tx_self_read on public.wallet_transactions for select to authenticated using(user_id=auth.uid());
revoke insert,update,delete on public.wallet_accounts,public.wallet_transactions from anon,authenticated;

-- Solde dérivé uniquement des opérations confirmées. Une opération ne peut être créditée qu'une fois.
create or replace function public.my_wallet_v2() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare uid uuid:=auth.uid(); result jsonb;
begin
 if uid is null then raise exception 'Connexion requise'; end if;
 insert into public.wallet_accounts(user_id,currency) values(uid,'HTG'),(uid,'USD') on conflict(user_id,currency) do nothing;
 select jsonb_build_object(
   'balances', coalesce((select jsonb_object_agg(currency, balance) from (
     select a.currency, coalesce(sum(case when t.status='successful' then
       case when t.kind in ('withdrawal','purchase','subscription_fee') then -t.amount_minor-t.fee_minor else t.amount_minor-t.fee_minor end else 0 end),0) balance
     from public.wallet_accounts a left join public.wallet_transactions t on t.account_id=a.id
     where a.user_id=uid group by a.currency) b),'{}'::jsonb),
   'transactions', coalesce((select jsonb_agg(jsonb_build_object('id',id,'reference',reference,'kind',kind,'status',status,'amount_minor',amount_minor,'fee_minor',fee_minor,'currency',currency,'provider',provider,'created_at',created_at) order by created_at desc)
      from (select * from public.wallet_transactions where user_id=uid order by created_at desc limit 50) recent),'[]'::jsonb)
 ) into result;
 return result;
end $$;
grant execute on function public.my_wallet_v2() to authenticated;

-- Création idempotente d'une intention de recharge ; aucun crédit ici.
create or replace function public.create_wallet_topup(p_amount_minor bigint,p_currency text,p_reference text) returns uuid
language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); aid uuid; tid uuid;
begin
 if uid is null then raise exception 'Connexion requise'; end if;
 if p_currency not in ('HTG','USD') or p_amount_minor < 2000 or p_amount_minor > 50000000 then raise exception 'Montant hors limites'; end if;
 if p_reference !~ '^HTK-[A-F0-9-]{20,60}$' then raise exception 'Référence invalide'; end if;
 insert into public.wallet_accounts(user_id,currency) values(uid,p_currency) on conflict(user_id,currency) do update set user_id=excluded.user_id returning id into aid;
 insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider)
 values(aid,uid,p_reference,'topup','pending',p_amount_minor,p_currency,'plopplop') returning id into tid;
 return tid;
end $$;
grant execute on function public.create_wallet_topup(bigint,text,text) to authenticated;

-- Fonction service-role uniquement : vérifie la référence et crédite exactement une fois.
create or replace function public.confirm_wallet_topup(p_reference text,p_provider_transaction_id text,p_provider_amount_minor bigint) returns boolean
language plpgsql security definer set search_path=public as $$
declare t public.wallet_transactions;
begin
 select * into t from public.wallet_transactions where reference=p_reference for update;
 if t.id is null then raise exception 'Recharge inconnue'; end if;
 if t.status='successful' then return true; end if;
 if t.status not in ('pending','processing') then raise exception 'Recharge non payable'; end if;
 if t.amount_minor<>p_provider_amount_minor then update public.wallet_transactions set status='review',updated_at=now() where id=t.id; raise exception 'Montant fournisseur différent'; end if;
 update public.wallet_transactions set status='successful',provider_transaction_id=p_provider_transaction_id,updated_at=now() where id=t.id;
 return true;
end $$;
revoke all on function public.confirm_wallet_topup(text,text,bigint) from public,anon,authenticated;

-- La fonction serveur prépare le retrait. Le solde est vérifié/verrouillé côté serveur avant appel fournisseur.
create or replace function public.prepare_wallet_withdrawal(p_amount_minor bigint,p_currency text,p_phone text,p_reference text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); aid uuid; bal bigint; tid uuid;
begin
 if uid is null then raise exception 'Connexion requise'; end if;
 if p_currency <> 'HTG' then raise exception 'Les retraits Plop Plop sont actuellement uniquement en HTG'; end if;
 if p_phone !~ '^509[0-9]{8}$' then raise exception 'Numéro haïtien invalide'; end if;
 if p_amount_minor < 5000 or p_amount_minor > 50000000 then raise exception 'Montant de retrait hors limites'; end if;
 select id into aid from public.wallet_accounts where user_id=uid and currency=p_currency for update;
 if aid is null then raise exception 'Portefeuille introuvable'; end if;
 select coalesce(sum(case when status='successful' then case when kind in ('withdrawal','purchase','subscription_fee') then -amount_minor-fee_minor else amount_minor-fee_minor end else 0 end),0) into bal from public.wallet_transactions where account_id=aid;
 if bal < p_amount_minor then raise exception 'Solde insuffisant'; end if;
 if exists(select 1 from public.wallet_transactions where user_id=uid and kind='withdrawal' and status in ('pending','processing')) then raise exception 'Un retrait est déjà en cours'; end if;
 insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,recipient_phone)
 values(aid,uid,p_reference,'withdrawal','processing',p_amount_minor,p_currency,'plopplop',p_phone) returning id into tid;
 return jsonb_build_object('id',tid,'reference',p_reference,'amount_minor',p_amount_minor,'currency',p_currency,'phone',p_phone);
end $$;
grant execute on function public.prepare_wallet_withdrawal(bigint,text,text,text) to authenticated;

create or replace function public.finish_wallet_withdrawal(p_reference text,p_success boolean,p_provider_transaction_id text default null,p_fee_minor bigint default 0) returns boolean
language plpgsql security definer set search_path=public as $$
declare t public.wallet_transactions;
begin
 select * into t from public.wallet_transactions where reference=p_reference for update;
 if t.id is null then raise exception 'Retrait inconnu'; end if;
 if t.status in ('successful','failed') then return t.status='successful'; end if;
 if t.status <> 'processing' then raise exception 'Retrait non en cours'; end if;
 update public.wallet_transactions set status=case when p_success then 'successful' else 'failed' end,
   provider_transaction_id=case when p_success then p_provider_transaction_id else null end,
   fee_minor=case when p_success then greatest(p_fee_minor,0) else 0 end,updated_at=now() where id=t.id;
 return p_success;
end $$;
revoke all on function public.finish_wallet_withdrawal(text,boolean,text,bigint) from public,anon,authenticated;
