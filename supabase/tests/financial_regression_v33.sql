-- HAITIKET V33 — contrat de régression financier en lecture seule.
-- À exécuter sur Supabase STAGING après toutes les migrations. Aucun fixture ni mouvement financier.
-- psql "$STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/financial_regression_v33.sql

do $$
declare
  fn regprocedure;
  fn_name text;
  definer boolean;
  cfg text[];
  required_functions text[] := array[
    'public.pay_order_from_wallet(uuid)',
    'public.confirm_wallet_topup(text,text,bigint)',
    'public.prepare_wallet_withdrawal(bigint,text,text,text)',
    'public.finish_wallet_withdrawal(text,boolean,text,bigint)',
    'public.admin_execute_wallet_refund(uuid,text)',
    'public.confirm_pickup(uuid,text)',
    'public.confirm_delivery(uuid,text)'
  ];
begin
  -- Core tables and row-level security.
  if to_regclass('public.wallet_accounts') is null then raise exception 'V33 FAILED: wallet_accounts missing'; end if;
  if to_regclass('public.wallet_transactions') is null then raise exception 'V33 FAILED: wallet_transactions missing'; end if;
  if not (select relrowsecurity from pg_class where oid='public.wallet_accounts'::regclass) then
    raise exception 'V33 FAILED: RLS disabled on wallet_accounts';
  end if;
  if not (select relrowsecurity from pg_class where oid='public.wallet_transactions'::regclass) then
    raise exception 'V33 FAILED: RLS disabled on wallet_transactions';
  end if;
  if has_table_privilege('anon','public.wallet_transactions','INSERT') or
     has_table_privilege('authenticated','public.wallet_transactions','INSERT') or
     has_table_privilege('anon','public.wallet_transactions','UPDATE') or
     has_table_privilege('authenticated','public.wallet_transactions','UPDATE') or
     has_table_privilege('anon','public.wallet_transactions','DELETE') or
     has_table_privilege('authenticated','public.wallet_transactions','DELETE') then
    raise exception 'V33 FAILED: client roles can mutate wallet_transactions';
  end if;
  if not exists (select 1 from pg_indexes where schemaname='public' and tablename='wallet_transactions'
      and indexdef ilike '%unique%' and indexdef ilike '%(reference)%') then
    raise exception 'V33 FAILED: unique wallet transaction reference index missing';
  end if;
  if not exists (select 1 from pg_indexes where schemaname='public' and tablename='wallet_transactions'
      and indexname='wallet_provider_tx_unique' and indexdef ilike '%unique%') then
    raise exception 'V33 FAILED: provider transaction id unique index missing';
  end if;

  -- Sensitive functions must be SECURITY DEFINER with a pinned search_path.
  foreach fn_name in array required_functions loop
    fn := to_regprocedure(fn_name);
    if fn is null then raise exception 'V33 FAILED: required function missing: %', fn_name; end if;
    select p.prosecdef, p.proconfig into definer, cfg from pg_proc p where p.oid=fn;
    if not definer then raise exception 'V33 FAILED: SECURITY DEFINER missing: %', fn_name; end if;
    if not coalesce(array_to_string(cfg,','),'') ilike '%search_path=public%' then
      raise exception 'V33 FAILED: pinned search_path missing: %', fn_name;
    end if;
  end loop;

  -- Provider callbacks must be server-only; client can only invoke the internal checkout and admin-gated refund RPC.
  fn := to_regprocedure('public.confirm_wallet_topup(text,text,bigint)');
  if has_function_privilege('anon',fn,'EXECUTE') or has_function_privilege('authenticated',fn,'EXECUTE') then
    raise exception 'V33 FAILED: client role can confirm provider topup';
  end if;
  fn := to_regprocedure('public.finish_wallet_withdrawal(text,boolean,text,bigint)');
  if has_function_privilege('anon',fn,'EXECUTE') or has_function_privilege('authenticated',fn,'EXECUTE') then
    raise exception 'V33 FAILED: client role can finalize provider withdrawal';
  end if;
  fn := to_regprocedure('public.pay_order_from_wallet(uuid)');
  if has_function_privilege('anon',fn,'EXECUTE') or not has_function_privilege('authenticated',fn,'EXECUTE') then
    raise exception 'V33 FAILED: checkout RPC grants are incorrect';
  end if;
  fn := to_regprocedure('public.admin_execute_wallet_refund(uuid,text)');
  if has_function_privilege('anon',fn,'EXECUTE') or not has_function_privilege('authenticated',fn,'EXECUTE') then
    raise exception 'V33 FAILED: refund RPC grants are incorrect';
  end if;

  raise notice 'V33 REGRESSION CONTRACT OK: wallet RLS, client mutation grants, unique references, sensitive RPC grants and SECURITY DEFINER search_path checked. No money moved; no live payment tested.';
end $$;
