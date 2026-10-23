-- HAITIKET V40 — vérification structurelle du cycle commande/livraison.
-- Lecture seule : ne crée/modifie aucune commande, mission ou transaction.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
\echo '=== HAITIKET V40 / ORDER & DELIVERY CONTRACT ==='

DO $$
DECLARE missing text[] := ARRAY[]::text[]; tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['orders','order_status_events','delivery_jobs','order_pins','order_disputes','refund_requests'] LOOP
    IF to_regclass('public.' || tbl) IS NULL THEN missing := array_append(missing,tbl); END IF;
  END LOOP;
  IF cardinality(missing)>0 THEN
    RAISE EXCEPTION 'V40 FAIL: tables du cycle commande/livraison absentes: %', array_to_string(missing, ', ');
  END IF;
  RAISE NOTICE 'V40 PASS: tables du cycle commande/livraison présentes';
END $$;

DO $$
DECLARE fn text; p record; found_any boolean; bad text[] := ARRAY[]::text[];
BEGIN
  FOREACH fn IN ARRAY ARRAY['seller_set_order_status','confirm_pickup','confirm_delivery','confirm_handover','_set_order_status'] LOOP
    found_any := false;
    FOR p IN SELECT pr.oid, pr.prosecdef, pr.proconfig
             FROM pg_proc pr JOIN pg_namespace ns ON ns.oid=pr.pronamespace
             WHERE ns.nspname='public' AND pr.proname=fn LOOP
      found_any := true;
      IF NOT p.prosecdef THEN bad := array_append(bad, fn || '(not SECURITY DEFINER)'); END IF;
      IF NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) cfg WHERE cfg LIKE 'search_path=%') THEN
        bad := array_append(bad, fn || '(search_path not pinned)');
      END IF;
    END LOOP;
    IF NOT found_any THEN bad := array_append(bad, fn || '(missing)'); END IF;
  END LOOP;
  IF cardinality(bad)>0 THEN RAISE EXCEPTION 'V40 FAIL: fonctions de cycle non conformes: %', array_to_string(bad, ', '); END IF;
  RAISE NOTICE 'V40 PASS: fonctions critiques trouvées avec SECURITY DEFINER et search_path explicite';
END $$;

DO $$
DECLARE body text; fn text; markers text[]; marker text; bad text[] := ARRAY[]::text[];
BEGIN
  -- Vérifie que le code déployé contient des garde-fous attendus. Ce contrôle est structurel,
  -- il ne prouve pas à lui seul que les scénarios fonctionnent en pratique.
  FOR fn, markers IN
    SELECT 'seller_set_order_status', ARRAY['Changement de statut non autorisé','CONFIRMED','PREPARING','READY_FOR_PICKUP']
    UNION ALL SELECT 'confirm_pickup', ARRAY['READY_FOR_PICKUP','IN_TRANSIT','Paiement vérifié introuvable','order_disputes']
    UNION ALL SELECT 'confirm_delivery', ARRAY['IN_TRANSIT','DELIVERED','order_disputes','refund_requests']
  LOOP
    SELECT pg_get_functiondef(p.oid) INTO body
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=fn
    ORDER BY p.oid DESC LIMIT 1;
    IF body IS NULL THEN
      bad := array_append(bad, fn || '(definition unreadable)');
    ELSE
      FOREACH marker IN ARRAY markers LOOP
        IF position(marker IN body)=0 THEN bad := array_append(bad, fn || '(missing guard: ' || marker || ')'); END IF;
      END LOOP;
    END IF;
  END LOOP;
  IF cardinality(bad)>0 THEN RAISE EXCEPTION 'V40 FAIL: garde-fous manquants: %', array_to_string(bad, ', '); END IF;
  RAISE NOTICE 'V40 PASS: garde-fous textuels attendus présents';
END $$;

SELECT p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosecdef AS security_definer,
       p.proconfig AS configuration,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('seller_set_order_status','confirm_pickup','confirm_delivery','confirm_handover','_set_order_status')
ORDER BY p.proname, arguments;

SELECT 'V40 STRUCTURAL CONTRACT PASSED; no business rows or financial balances were changed.' AS result;
COMMIT;
