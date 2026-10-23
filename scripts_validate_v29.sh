#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SQL="$ROOT/supabase/migrations/0038_launch_readiness_audit_v29.sql"
REPO="$ROOT/lib/data/repo.dart"
ADMIN="$ROOT/lib/ui/admin2.dart"
for f in "$SQL" "$REPO" "$ADMIN"; do test -s "$f"; done
grep -q "run_launch_readiness_audit_v29" "$SQL"
grep -q "run_financial_reconciliation_v24" "$SQL"
grep -q "run_financial_guard_audit_v26" "$SQL"
grep -q "run_delivery_flow_audit_v27" "$SQL"
grep -q "run_commercial_flow_audit_v28" "$SQL"
grep -q "business_data_mutations_performed', false" "$SQL"
grep -q "adminRunLaunchReadinessAuditV29" "$REPO"
grep -q "Audit global de préparation au lancement V29" "$ADMIN"
grep -q "production_certified', false" "$SQL"
echo "V29 static checks: OK"
