-- HAITIKET V38 — audit de préparation au lancement, strictement en lecture seule.
-- À exécuter uniquement sur staging; aucune donnée métier n'est modifiée.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
\echo '=== HAITIKET V38 / PRÉPARATION AU LANCEMENT (READ ONLY) ==='
DO $$
DECLARE missing text[] := ARRAY[]::text[]; tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['wallet_accounts','wallet_transactions','orders','delivery_jobs','refund_requests'] LOOP
    IF to_regclass('public.' || tbl) IS NULL THEN missing := array_append(missing,tbl); END IF;
  END LOOP;
  IF cardinality(missing)>0 THEN RAISE EXCEPTION 'V38 FAIL: tables absentes: %', array_to_string(missing, ', '); END IF;
  RAISE NOTICE 'V38 PASS: tables financières critiques présentes';
END $$;
DO $$
DECLARE role_name text; tbl text; priv text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN
      FOREACH tbl IN ARRAY ARRAY['wallet_accounts','wallet_transactions'] LOOP
        FOREACH priv IN ARRAY ARRAY['INSERT','UPDATE','DELETE','TRUNCATE'] LOOP
          IF has_table_privilege(role_name, 'public.' || tbl, priv) THEN
            RAISE EXCEPTION 'V38 FAIL: rôle % possède % sur public.%', role_name, priv, tbl;
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END LOOP;
  RAISE NOTICE 'V38 PASS: aucun droit direct d’écriture client détecté sur les portefeuilles';
END $$;
DO $$
DECLARE fn text; p record; found_any boolean; bad text[] := ARRAY[]::text[];
BEGIN
  FOREACH fn IN ARRAY ARRAY['confirm_wallet_topup','finish_wallet_withdrawal','pay_order_from_wallet','confirm_pickup','confirm_delivery','admin_execute_wallet_refund'] LOOP
    found_any := false;
    FOR p IN SELECT pr.oid, pr.prosecdef, pr.proconfig FROM pg_proc pr JOIN pg_namespace ns ON ns.oid=pr.pronamespace WHERE ns.nspname='public' AND pr.proname=fn LOOP
      found_any := true;
      IF NOT p.prosecdef OR NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) cfg WHERE cfg LIKE 'search_path=%') THEN
        bad := array_append(bad, fn || '(SECURITY DEFINER/search_path)');
      END IF;
    END LOOP;
    IF NOT found_any THEN bad := array_append(bad, fn || '(absente)'); END IF;
  END LOOP;
  IF cardinality(bad)>0 THEN RAISE EXCEPTION 'V38 FAIL: fonctions critiques non conformes: %', array_to_string(bad, ', '); END IF;
  RAISE NOTICE 'V38 PASS: fonctions critiques en SECURITY DEFINER avec search_path explicite';
END $$;
SELECT p.proname AS fonction, pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosecdef AS security_definer, p.proconfig AS configuration,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN ('confirm_wallet_topup','finish_wallet_withdrawal','pay_order_from_wallet','confirm_pickup','confirm_delivery','admin_execute_wallet_refund')
ORDER BY p.proname, arguments;
SELECT 'V38 STRUCTURAL GATE PASSED; no payments, balances, or business rows were changed.' AS result;
COMMIT;
