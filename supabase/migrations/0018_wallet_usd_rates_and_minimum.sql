-- HAITIKET 0018: corrige le minimum USD et sépare les taux de recharge et de retrait.
-- Les anciens réglages restent compatibles via usd_htg_rate comme valeur de secours.

create or replace function public.wallet_exchange_rate()
returns numeric language plpgsql stable security definer set search_path=public as $$
declare r numeric;
begin
  select value::numeric into r from public.platform_settings where key='usd_htg_topup_rate';
  if r is null then select value::numeric into r from public.platform_settings where key='usd_htg_rate'; end if;
  if r is null or r <= 0 then return null; end if;
  return r;
exception when others then return null;
end $$;
revoke all on function public.wallet_exchange_rate() from public,anon;
grant execute on function public.wallet_exchange_rate() to authenticated;

create or replace function public.wallet_withdraw_exchange_rate()
returns numeric language plpgsql stable security definer set search_path=public as $$
declare r numeric;
begin
  select value::numeric into r from public.platform_settings where key='usd_htg_withdraw_rate';
  if r is null then select value::numeric into r from public.platform_settings where key='usd_htg_rate'; end if;
  if r is null or r <= 0 then return null; end if;
  return r;
exception when others then return null;
end $$;
revoke all on function public.wallet_withdraw_exchange_rate() from public,anon;
grant execute on function public.wallet_withdraw_exchange_rate() to authenticated;

create or replace function public.create_wallet_topup_fx(
  p_amount_minor bigint, p_currency text, p_reference text,
  p_provider_amount_minor bigint, p_exchange_rate numeric
) returns uuid language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); aid uuid; tid uuid; r numeric; expected_provider bigint;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  if p_currency not in ('HTG','USD') then raise exception 'Devise invalide'; end if;
  if (p_currency='USD' and (p_amount_minor < 100 or p_amount_minor > 50000000))
     or (p_currency='HTG' and (p_amount_minor < 2000 or p_amount_minor > 50000000)) then
    raise exception 'Montant hors limites';
  end if;
  if p_reference !~ '^HTK-[A-F0-9-]{20,60}$' then raise exception 'Référence invalide'; end if;
  if p_currency='USD' then
    select value::numeric into r from public.platform_settings where key='usd_htg_topup_rate';
    if r is null then select value::numeric into r from public.platform_settings where key='usd_htg_rate'; end if;
    if r is null or r<=0 then raise exception 'Taux de recharge USD → HTG non configuré'; end if;
    if p_exchange_rate is null or p_exchange_rate<>r then raise exception 'Le taux de recharge a changé; recommence la demande'; end if;
    expected_provider:=round((p_amount_minor::numeric/100)*r*100)::bigint;
  else
    r:=null; expected_provider:=p_amount_minor;
  end if;
  if expected_provider<>p_provider_amount_minor or expected_provider<2000 or expected_provider>50000000 then
    raise exception 'Montant converti hors limites ou incohérent';
  end if;
  insert into public.wallet_accounts(user_id,currency) values(uid,p_currency)
    on conflict(user_id,currency) do update set user_id=excluded.user_id returning id into aid;
  insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
  values(aid,uid,p_reference,'topup','pending',p_amount_minor,p_currency,'plopplop',jsonb_build_object(
    'provider_amount_minor',expected_provider,'payment_currency','HTG','wallet_currency',p_currency,'exchange_rate',r
  )) returning id into tid;
  return tid;
end $$;
revoke all on function public.create_wallet_topup_fx(bigint,text,text,bigint,numeric) from public,anon;
grant execute on function public.create_wallet_topup_fx(bigint,text,text,bigint,numeric) to authenticated;

create or replace function public.admin_set_setting(p_key text,p_value text) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_key not in ('commission_bps','reservation_minutes','delivery_flat_minor','usd_htg_rate','usd_htg_topup_rate','usd_htg_withdraw_rate','bazar_fee_usd','shop_fee_usd','enforce_shop_plan','referral_reward_minor') then raise exception 'Réglage inconnu'; end if;
  if p_key='enforce_shop_plan' then
    if p_value not in ('true','false') then raise exception 'Valeur attendue : true ou false'; end if;
  elsif p_key in ('usd_htg_rate','usd_htg_topup_rate','usd_htg_withdraw_rate','bazar_fee_usd','shop_fee_usd') then
    if p_value !~ '^[0-9]{1,6}(\.[0-9]{1,4})?$' or p_value::numeric<=0 then raise exception 'Nombre positif requis'; end if;
  else
    if p_value !~ '^[0-9]{1,9}$' then raise exception 'Nombre entier requis'; end if;
  end if;
  insert into public.platform_settings(key,value) values(p_key,trim(p_value))
  on conflict(key) do update set value=excluded.value,updated_at=now();
  insert into public.admin_audit_logs(actor,action,resource,reason) values(auth.uid(),'set_setting',p_key,left(p_value,100));
end $$;
grant execute on function public.admin_set_setting(text,text) to authenticated;
