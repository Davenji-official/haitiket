-- HAITIKET V32: pré-vol financier en lecture seule.
-- À exécuter uniquement sur une base Supabase de STAGING après application des migrations.
-- Exemple: psql "$STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/financial_preflight_v32.sql
-- Ce script ne crée, ne modifie et ne supprime aucune donnée métier.

do $$
declare
  required_tables text[] := array[
    'public.orders',
    'public.wallet_accounts',
    'public.wallet_transactions',
    'public.refund_requests',
    'public.order_disputes',
    'public.delivery_jobs'
  ];
  item text;
  fn regprocedure;
  fn_definer boolean;
  fn_config text[];
begin
  foreach item in array required_tables loop
    if to_regclass(item) is null then
      raise exception 'V32 PREFLIGHT FAILED: table absente: %', item;
    end if;
  end loop;

  fn := to_regprocedure('public.pay_order_from_wallet(uuid)');
  if fn is null then raise exception 'V32 PREFLIGHT FAILED: pay_order_from_wallet(uuid) absent'; end if;
  select p.prosecdef, p.proconfig into fn_definer, fn_config
    from pg_proc p where p.oid = fn;
  if not fn_definer then raise exception 'V32 PREFLIGHT FAILED: pay_order_from_wallet doit être SECURITY DEFINER'; end if;
  if not coalesce(array_to_string(fn_config, ','), '') like '%search_path=public%' then
    raise exception 'V32 PREFLIGHT FAILED: search_path public absent de pay_order_from_wallet';
  end if;
  if has_function_privilege('anon', fn, 'EXECUTE') then
    raise exception 'V32 PREFLIGHT FAILED: anon peut exécuter pay_order_from_wallet';
  end if;
  if not has_function_privilege('authenticated', fn, 'EXECUTE') then
    raise exception 'V32 PREFLIGHT FAILED: authenticated ne peut pas exécuter pay_order_from_wallet';
  end if;

  fn := to_regprocedure('public.admin_execute_wallet_refund(uuid,text)');
  if fn is null then raise exception 'V32 PREFLIGHT FAILED: admin_execute_wallet_refund(uuid,text) absent'; end if;
  select p.prosecdef, p.proconfig into fn_definer, fn_config
    from pg_proc p where p.oid = fn;
  if not fn_definer then raise exception 'V32 PREFLIGHT FAILED: admin_execute_wallet_refund doit être SECURITY DEFINER'; end if;
  if not coalesce(array_to_string(fn_config, ','), '') like '%search_path=public%' then
    raise exception 'V32 PREFLIGHT FAILED: search_path public absent de admin_execute_wallet_refund';
  end if;
  if has_function_privilege('anon', fn, 'EXECUTE') then
    raise exception 'V32 PREFLIGHT FAILED: anon peut exécuter admin_execute_wallet_refund';
  end if;
  if exists (
    select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where p.oid = fn and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'V32 PREFLIGHT FAILED: PUBLIC peut exécuter admin_execute_wallet_refund';
  end if;
  if not has_function_privilege('authenticated', fn, 'EXECUTE') then
    raise exception 'V32 PREFLIGHT FAILED: authenticated ne peut pas appeler le RPC administrateur (l'accès reste contrôlé dans la fonction)';
  end if;

  raise notice 'V32 PREFLIGHT OK: tables financières, signatures RPC, SECURITY DEFINER, search_path et privilèges de base vérifiés. Aucun mouvement financier effectué.';
end $$;
