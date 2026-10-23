-- HAITIKET V37 — contrôles structurels supplémentaires, strictement en lecture seule.
-- Usage: psql "$STAGING_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f ce_fichier.sql
-- N'exécute aucune RPC métier, ne crée aucune donnée et ne modifie aucun solde.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
\echo '=== HAITIKET V37 / INTÉGRITÉ STRUCTURELLE (READ ONLY) ==='

DO $$
DECLARE missing text[] := ARRAY[]::text[];
obj text;
BEGIN
  FOREACH obj IN ARRAY ARRAY[
    'wallet_accounts','wallet_transactions','orders','delivery_jobs',
    'refund_requests','shop_subscriptions','bazar_listings'
  ] LOOP
    IF to_regclass('public.' || obj) IS NULL THEN
      missing := array_append(missing, obj);
    END IF;
  END LOOP;
  IF cardinality(missing) > 0 THEN
    RAISE EXCEPTION 'V37 FAIL: tables missing: %', array_to_string(missing, ', ');
  END IF;
  RAISE NOTICE 'V37 PASS: core wallet/order/delivery/refund tables exist';
END $$;

DO $$
DECLARE tbl text; enabled boolean; policy_count integer;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['wallet_accounts','wallet_transactions'] LOOP
    SELECT c.relrowsecurity INTO enabled
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname=tbl;
    IF coalesce(enabled,false) IS NOT TRUE THEN
      RAISE EXCEPTION 'V37 FAIL: RLS disabled on public.%', tbl;
    END IF;
    SELECT count(*) INTO policy_count
    FROM pg_policies WHERE schemaname='public' AND tablename=tbl;
    IF policy_count = 0 THEN
      RAISE EXCEPTION 'V37 FAIL: no RLS policy found for public.%', tbl;
    END IF;
  END LOOP;
  RAISE NOTICE 'V37 PASS: wallet RLS enabled and policies present (policy correctness still needs review)';
END $$;

DO $$
DECLARE has_ref_unique boolean; has_provider_unique boolean; has_currency_check boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname='public'
      AND tablename='wallet_transactions'
      AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%reference%'
  ) INTO has_ref_unique;
  IF NOT has_ref_unique THEN
    RAISE EXCEPTION 'V37 FAIL: unique wallet transaction reference index/constraint not found';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname='public'
      AND indexname='wallet_provider_tx_unique'
  ) INTO has_provider_unique;
  IF NOT has_provider_unique THEN
    RAISE EXCEPTION 'V37 FAIL: wallet_provider_tx_unique missing';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid=c.conrelid
    JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE n.nspname='public' AND t.relname='wallet_transactions'
      AND c.contype='c' AND pg_get_constraintdef(c.oid) ILIKE '%currency%'
  ) INTO has_currency_check;
  IF NOT has_currency_check THEN
    RAISE EXCEPTION 'V37 FAIL: currency CHECK constraint not found on wallet_transactions';
  END IF;
  RAISE NOTICE 'V37 PASS: unique references, provider idempotency index, currency constraint exist';
END $$;

\echo '=== V37 / Fonctions sensibles présentes ==='
SELECT expected.function_name,
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname=expected.function_name) AS present
FROM (VALUES
  ('create_wallet_topup'), ('confirm_wallet_topup'),
  ('prepare_wallet_withdrawal'), ('finish_wallet_withdrawal'),
  ('pay_order_from_wallet'), ('confirm_pickup'), ('confirm_delivery'),
  ('admin_execute_wallet_refund')
) AS expected(function_name)
ORDER BY expected.function_name;

DO $$
DECLARE missing text[] := ARRAY[]::text[]; fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'create_wallet_topup','confirm_wallet_topup','prepare_wallet_withdrawal',
    'finish_wallet_withdrawal','pay_order_from_wallet','confirm_pickup',
    'confirm_delivery','admin_execute_wallet_refund'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                   WHERE n.nspname='public' AND p.proname=fn) THEN
      missing := array_append(missing, fn);
    END IF;
  END LOOP;
  IF cardinality(missing)>0 THEN
    RAISE EXCEPTION 'V37 FAIL: critical functions missing: %', array_to_string(missing, ', ');
  END IF;
  RAISE NOTICE 'V37 PASS: expected critical functions exist';
END $$;

\echo '=== V37 / Triggers financiers sur commandes et livraisons (à examiner) ==='
SELECT c.relname AS table_name, t.tgname AS trigger_name,
       pg_get_triggerdef(t.oid, true) AS trigger_definition
FROM pg_trigger t
JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND NOT t.tgisinternal
  AND (c.relname IN ('orders','delivery_jobs','refund_requests'))
ORDER BY c.relname, t.tgname;

SELECT 'V37 STRUCTURAL CHECKS PASSED; no payment scenario was executed.' AS result;
COMMIT;
