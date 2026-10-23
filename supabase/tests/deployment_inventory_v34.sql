-- HAITIKET V34 — inventaire de déploiement en lecture seule.
-- À exécuter sur STAGING, puis sur PRODUCTION en fenêtre de maintenance :
-- psql "$STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/deployment_inventory_v34.sql
-- Aucun INSERT/UPDATE/DELETE/DDL et aucun mouvement financier.

\echo '=== V34 / 1. Migrations Supabase enregistrées ==='
select case
  when to_regclass('supabase_migrations.schema_migrations') is null
    then 'TABLE HISTORIQUE ABSENTE : vérifier le projet et les droits de lecture'
  else 'Historique Supabase trouvé'
end as migration_history_status;

do $$
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    raise notice 'Historique disponible : les lignes sont affichées dans la requête suivante.';
  end if;
end $$;

-- Dynamic query avoids failing when the migration-history table is not visible.
select format(
  'select version, name from %s order by version',
  to_regclass('supabase_migrations.schema_migrations')
) as migration_history_query
where to_regclass('supabase_migrations.schema_migrations') is not null \gexec

\echo '=== V34 / 2. Objets financiers essentiels ==='
select expected.object_name,
       to_regclass('public.' || expected.object_name) is not null as exists_in_database
from (values
  ('wallet_accounts'), ('wallet_transactions'), ('orders'),
  ('refund_requests'), ('delivery_jobs'), ('shop_subscriptions'),
  ('bazar_listings'), ('app_settings')
) as expected(object_name)
order by expected.object_name;

\echo '=== V34 / 3. Fonctions de paiement, portefeuille, livraison et anciennes intégrations ==='
select n.nspname as schema_name,
       p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       p.prosecdef as security_definer,
       coalesce(array_to_string(p.proconfig, ', '), '') as function_config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (p.proname ilike '%wallet%'
    or p.proname ilike '%plop%'
    or p.proname ilike '%bazik%'
    or p.proname ilike '%payment%'
    or p.proname ilike '%refund%'
    or p.proname ilike '%order%'
    or p.proname ilike '%delivery%'
    or p.proname ilike '%courier%')
order by p.proname, arguments;

\echo '=== V34 / 4. RLS des tables financières ==='
select c.relname as table_name,
       c.relrowsecurity as rls_enabled,
       c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r', 'p')
  and (c.relname ilike '%wallet%'
    or c.relname ilike '%payment%'
    or c.relname ilike '%refund%'
    or c.relname ilike '%payout%')
order by c.relname;

\echo '=== V34 / 5. Triggers liés aux ordres, remboursements et livraison ==='
select n.nspname as schema_name,
       c.relname as table_name,
       t.tgname as trigger_name,
       pg_get_triggerdef(t.oid, true) as trigger_definition
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where not t.tgisinternal
  and n.nspname = 'public'
  and (c.relname ilike '%order%'
    or c.relname ilike '%refund%'
    or c.relname ilike '%delivery%'
    or c.relname ilike '%wallet%')
order by c.relname, t.tgname;

\echo '=== V34 / 6. Fin de l’inventaire ==='
select 'READ-ONLY INVENTORY COMPLETE — vérifier les résultats, les Edge Functions déployées, les secrets et les webhooks dans Supabase Dashboard.' as result;
