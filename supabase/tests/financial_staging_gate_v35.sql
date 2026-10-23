-- HAITIKET V35 — garde de staging financière, lecture seule.
-- Exécuter uniquement sur le projet STAGING avec un rôle autorisé à lire les catalogues.
-- psql "$STAGING_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f supabase/tests/financial_staging_gate_v35.sql
-- Ne crée/modifie aucune donnée et n'appelle aucune fonction métier de paiement.
\set ON_ERROR_STOP on
\echo '=== HAITIKET V35 / GATE FINANCIÈRE STAGING (LECTURE SEULE) ==='

DO $$
DECLARE missing text[] := ARRAY[]::text[];
obj text;
BEGIN
  FOREACH obj IN ARRAY ARRAY[
    'wallet_accounts','wallet_transactions','orders','refund_requests','delivery_jobs',
    'shop_subscriptions','bazar_listings','app_settings'
  ] LOOP
    IF to_regclass('public.' || obj) IS NULL THEN missing := array_append(missing, obj); END IF;
  END LOOP;
  IF cardinality(missing) > 0 THEN
    RAISE EXCEPTION 'V35 FAIL: tables required are missing: %', array_to_string(missing, ', ');
  END IF;
  RAISE NOTICE 'V35 PASS: required tables are present';
END $$;

DO $$
DECLARE bad text[] := ARRAY[]::text[];
tbl text;
rls boolean;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['wallet_accounts','wallet_transactions'] LOOP
    SELECT c.relrowsecurity INTO rls
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname=tbl;
    IF coalesce(rls,false) IS NOT TRUE THEN bad := array_append(bad, tbl); END IF;
  END LOOP;
  IF cardinality(bad)>0 THEN RAISE EXCEPTION 'V35 FAIL: RLS not enabled on: %', array_to_string(bad, ', '); END IF;
  RAISE NOTICE 'V35 PASS: RLS enabled on wallet tables';
END $$;

DO $$
DECLARE fn text;
sig text;
proc_oid oid;
secdef boolean;
cfg text[];
BEGIN
  FOR fn, sig IN SELECT * FROM (VALUES
    ('my_wallet_v2',''),
    ('create_wallet_topup','bigint, text, text'),
    ('confirm_wallet_topup','text, text, bigint'),
    ('prepare_wallet_withdrawal','bigint, text, text, text'),
    ('finish_wallet_withdrawal','text, boolean, text, bigint'),
    ('pay_order_from_wallet','uuid')
  ) expected(name,args)
  LOOP
    SELECT p.oid, p.prosecdef, p.proconfig INTO proc_oid, secdef, cfg
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=fn
      AND (sig='' OR pg_get_function_identity_arguments(p.oid)=sig)
    ORDER BY p.oid DESC LIMIT 1;
    IF proc_oid IS NULL THEN RAISE EXCEPTION 'V35 FAIL: function missing: public.%(%)', fn, sig; END IF;
    IF NOT coalesce(secdef,false) THEN RAISE EXCEPTION 'V35 FAIL: expected SECURITY DEFINER: public.%(%)', fn, sig; END IF;
    IF NOT EXISTS (SELECT 1 FROM unnest(coalesce(cfg,ARRAY[]::text[])) c WHERE c LIKE 'search_path=public%') THEN
      RAISE EXCEPTION 'V35 FAIL: pinned search_path=public missing on public.%(%)', fn, sig;
    END IF;
  END LOOP;
  RAISE NOTICE 'V35 PASS: critical RPC functions exist with SECURITY DEFINER and pinned search_path';
END $$;

DO $$
DECLARE idx boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND indexname='wallet_provider_tx_unique'
  ) INTO idx;
  IF NOT idx THEN RAISE EXCEPTION 'V35 FAIL: wallet_provider_tx_unique index missing'; END IF;
  RAISE NOTICE 'V35 PASS: provider transaction idempotency index exists';
END $$;

-- Affiche les permissions effectives à examiner. Le résultat est informatif :
-- les rôles, propriétaires et configurations peuvent différer entre environnements.
\echo '=== Grants client sur tables de portefeuille (aucun droit d’écriture attendu) ==='
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema='public'
  AND table_name IN ('wallet_accounts','wallet_transactions')
  AND grantee IN ('anon','authenticated')
ORDER BY table_name, grantee, privilege_type;

\echo '=== Fonctions serveur sensibles : EXECUTE ne doit pas être accordé aux rôles clients ==='
SELECT p.proname AS function_name,
       has_function_privilege('anon',p.oid,'EXECUTE') AS anon_can_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_can_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('confirm_wallet_topup','finish_wallet_withdrawal')
ORDER BY p.proname;

SELECT 'V35 STRUCTURAL GATE PASSED — permissions listées ci-dessus à examiner; aucun paiement exécuté.' AS result;
