-- HAITIKET 0016: recharge du portefeuille USD payée en HTG via Plop Plop.
-- Le taux est lu côté serveur; le client ne décide jamais du montant converti.

create or replace function public.wallet_exchange_rate()
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare r numeric;
begin
  select value::numeric into r
  from public.platform_settings
  where key = 'usd_htg_rate';
  if r is null or r <= 0 then return null; end if;
  return r;
exception when others then
  return null;
end;
$$;
revoke all on function public.wallet_exchange_rate() from public, anon;
grant execute on function public.wallet_exchange_rate() to authenticated;

-- Crée une intention en devise cible et mémorise le montant exact attendu par le fournisseur (HTG).
create or replace function public.create_wallet_topup_fx(
  p_amount_minor bigint,
  p_currency text,
  p_reference text,
  p_provider_amount_minor bigint,
  p_exchange_rate numeric
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  aid uuid;
  tid uuid;
  r numeric;
  expected_provider bigint;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  if p_currency not in ('HTG','USD') then raise exception 'Devise invalide'; end if;
  if p_amount_minor < 2000 or p_amount_minor > 50000000 then raise exception 'Montant hors limites'; end if;
  if p_reference !~ '^HTK-[A-F0-9-]{20,60}$' then raise exception 'Référence invalide'; end if;

  if p_currency = 'USD' then
    select value::numeric into r from public.platform_settings where key='usd_htg_rate';
    if r is null or r <= 0 then raise exception 'Taux USD → HTG non configuré'; end if;
    if p_exchange_rate is null or p_exchange_rate <> r then raise exception 'Le taux a changé; recommence la recharge'; end if;
    expected_provider := round((p_amount_minor::numeric / 100) * r * 100)::bigint;
  else
    r := null;
    expected_provider := p_amount_minor;
  end if;

  if expected_provider <> p_provider_amount_minor or expected_provider < 2000 or expected_provider > 50000000 then
    raise exception 'Montant converti hors limites ou incohérent';
  end if;

  insert into public.wallet_accounts(user_id,currency)
    values(uid,p_currency) on conflict(user_id,currency) do update set user_id=excluded.user_id returning id into aid;

  insert into public.wallet_transactions(
    account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata
  ) values (
    aid,uid,p_reference,'topup','pending',p_amount_minor,p_currency,'plopplop',
    jsonb_build_object(
      'provider_amount_minor', expected_provider,
      'payment_currency', 'HTG',
      'wallet_currency', p_currency,
      'exchange_rate', r
    )
  ) returning id into tid;
  return tid;
end;
$$;
revoke all on function public.create_wallet_topup_fx(bigint,text,text,bigint,numeric) from public, anon;
grant execute on function public.create_wallet_topup_fx(bigint,text,text,bigint,numeric) to authenticated;

-- Confirmation atomique: compare le montant réellement payé en HTG au montant HTG attendu,
-- tout en créditant le montant_minor enregistré dans la devise du portefeuille.
create or replace function public.confirm_wallet_topup(
  p_reference text,
  p_provider_transaction_id text,
  p_provider_amount_minor bigint
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  t public.wallet_transactions;
  expected_provider bigint;
begin
  select * into t from public.wallet_transactions where reference=p_reference for update;
  if t.id is null then raise exception 'Recharge inconnue'; end if;
  if t.status='successful' then return true; end if;
  if t.status not in ('pending','processing') then raise exception 'Recharge non payable'; end if;
  if coalesce(trim(p_provider_transaction_id),'') = '' then raise exception 'Identifiant fournisseur manquant'; end if;
  expected_provider := coalesce((t.metadata->>'provider_amount_minor')::bigint, t.amount_minor);
  if expected_provider <> p_provider_amount_minor then
    update public.wallet_transactions set status='review',updated_at=now() where id=t.id;
    raise exception 'Montant fournisseur différent';
  end if;
  if exists (
    select 1 from public.wallet_transactions
    where provider='plopplop' and provider_transaction_id=p_provider_transaction_id and id<>t.id
  ) then raise exception 'Transaction fournisseur déjà utilisée'; end if;
  update public.wallet_transactions
    set status='successful', provider_transaction_id=p_provider_transaction_id, updated_at=now()
    where id=t.id;
  return true;
end;
$$;
revoke all on function public.confirm_wallet_topup(text,text,bigint) from public,anon,authenticated;
