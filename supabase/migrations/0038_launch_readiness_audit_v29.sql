-- HAITIKET V29 — rapport de préparation au lancement.
-- Appelle les audits existants. Ne modifie aucune commande, aucun statut commercial,
-- aucun portefeuille et aucun mouvement financier. Les audits appelés écrivent leurs journaux d'audit.

create or replace function public.run_launch_readiness_audit_v29()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  finance_report jsonb;
  guard_report jsonb;
  delivery_report jsonb;
  commercial_report jsonb;
  issues bigint := 0;
  warnings bigint := 0;
  final_status text;
  report jsonb;
begin
  if actor_id is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : déverrouillez la console administrateur';
  end if;

  -- Une fonction manquante fait échouer l'audit au lieu d'annoncer une fausse préparation.
  finance_report := public.run_financial_reconciliation_v24();
  guard_report := public.run_financial_guard_audit_v26();
  delivery_report := public.run_delivery_flow_audit_v27();
  commercial_report := public.run_commercial_flow_audit_v28();

  issues :=
    coalesce((finance_report->>'issue_count')::bigint, 0) +
    coalesce((guard_report->>'issue_count')::bigint, 0) +
    coalesce((delivery_report->>'issue_count')::bigint, 0) +
    coalesce((commercial_report->>'issue_count')::bigint, 0);

  warnings :=
    coalesce((finance_report->>'warning_count')::bigint, 0) +
    coalesce((guard_report->>'warning_count')::bigint, 0) +
    coalesce((delivery_report->>'warning_count')::bigint, 0) +
    coalesce((commercial_report->>'warning_count')::bigint, 0);

  final_status := case when issues > 0 then 'issues_found'
                       when warnings > 0 then 'warnings'
                       else 'clean' end;

  report := jsonb_build_object(
    'generated_at', now(),
    'status', final_status,
    'issue_count', issues,
    'warning_count', warnings,
    'financial_reconciliation_v24', finance_report,
    'financial_guards_v26', guard_report,
    'delivery_v27', delivery_report,
    'commercial_v28', commercial_report,
    'business_data_mutations_performed', false,
    'audit_logs_written', true,
    'production_certified', false,
    'note', 'Rapport agrégé. Un statut clean signifie uniquement que les contrôles présents ne remontent pas d’anomalie; cela ne remplace pas les tests de staging, la compilation Flutter ni la vérification du prestataire.'
  );

  insert into public.admin_audit_logs(actor, action, resource, reason)
  values(actor_id, 'launch_readiness_audit_v29', 'launch_readiness',
    'status=' || final_status || '; issues=' || issues::text || '; warnings=' || warnings::text || '; read-only business data');

  return report;
end;
$$;

revoke all on function public.run_launch_readiness_audit_v29() from public, anon;
grant execute on function public.run_launch_readiness_audit_v29() to authenticated;
comment on function public.run_launch_readiness_audit_v29() is
'V29 : agrège les audits financiers, de garde-fous, de livraison et commerciaux; ne modifie pas les données métier ni les soldes.';
