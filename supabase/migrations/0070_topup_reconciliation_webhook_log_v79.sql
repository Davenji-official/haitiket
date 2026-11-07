-- HAITIKET V79 — recharges Plop Plop : journal du webhook, rapprochement administrateur, notifications de portefeuille.
-- À appliquer APRÈS 0069. Idempotent.

-- 1. Journal de CHAQUE appel du webhook (permet de savoir si Plop Plop atteint bien votre fonction)
create table if not exists public.payment_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'plopplop',
  event text, reference text, signature_ok boolean,
  outcome text not null, http_status integer, detail text,
  created_at timestamptz not null default now()
);
create index if not exists payment_webhook_events_created_idx on public.payment_webhook_events(created_at desc);
alter table public.payment_webhook_events enable row level security;
revoke all on public.payment_webhook_events from anon, authenticated;

create or replace function public.admin_list_webhook_events(p_limit integer default 40)
returns table(id uuid, provider text, event text, reference text, signature_ok boolean, outcome text, http_status integer, detail text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query select e.id, e.provider, e.event, e.reference, e.signature_ok, e.outcome, e.http_status, e.detail, e.created_at
    from public.payment_webhook_events e order by e.created_at desc limit greatest(1, least(coalesce(p_limit,40), 200));
end $$;
revoke all on function public.admin_list_webhook_events(integer) from public, anon;
grant execute on function public.admin_list_webhook_events(integer) to authenticated;

-- 2. Liste des recharges pour le rapprochement
create or replace function public.admin_list_topups(p_status text default 'all', p_limit integer default 60)
returns table(id uuid, reference text, user_id uuid, user_name text, email text, amount_minor bigint, currency text, status text,
              provider_transaction_id text, reason text, created_at timestamptz, updated_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query
  select t.id, t.reference, t.user_id, p.display_name, u.email::text, t.amount_minor, t.currency, t.status, t.provider_transaction_id,
         coalesce(t.metadata->>'review_reason', t.metadata->>'reason'), t.created_at, t.updated_at
  from public.wallet_transactions t
  left join public.profiles p on p.id = t.user_id
  left join auth.users u on u.id = t.user_id
  where t.kind = 'topup' and (coalesce(p_status,'all') = 'all' or t.status = p_status)
  order by t.created_at desc limit greatest(1, least(coalesce(p_limit,60), 200));
end $$;
revoke all on function public.admin_list_topups(text,integer) from public, anon;
grant execute on function public.admin_list_topups(text,integer) to authenticated;

-- 3. Notifications de portefeuille (recharge confirmée, retrait effectué, opération échouée)
create or replace function public._trg_wallet_notify() returns trigger language plpgsql security definer set search_path = public as $$
declare v_amt text := (new.amount_minor / 100.0)::numeric(14,2) || ' ' || new.currency;
begin
  if new.status = 'successful' and old.status is distinct from 'successful' then
    if new.kind = 'topup' then
      insert into public.notifications(user_id, kind, title, body, ref) values (new.user_id, 'wallet', 'Recharge confirmée', v_amt || ' ajoutés à votre portefeuille.', new.id);
    elsif new.kind = 'withdrawal' then
      insert into public.notifications(user_id, kind, title, body, ref) values (new.user_id, 'wallet', 'Retrait effectué', v_amt || ' envoyés vers votre compte mobile.', new.id);
    end if;
  elsif new.status = 'failed' and old.status is distinct from 'failed' and new.kind in ('topup','withdrawal') then
    insert into public.notifications(user_id, kind, title, body, ref) values (new.user_id, 'wallet', case when new.kind = 'topup' then 'Recharge échouée' else 'Retrait échoué' end, v_amt || ' : l''opération n''a pas abouti.', new.id);
  end if;
  return new;
end $$;
drop trigger if exists wallet_notify on public.wallet_transactions;
create trigger wallet_notify after update of status on public.wallet_transactions for each row execute function public._trg_wallet_notify();
