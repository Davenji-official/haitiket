#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SQL="$ROOT/supabase/migrations/0036_delivery_flow_hardening_v27.sql"
REPO="$ROOT/lib/data/repo.dart"
ADMIN="$ROOT/lib/ui/admin2.dart"
test -s "$SQL"
grep -q "create or replace function public.confirm_pickup" "$SQL"
grep -q "create or replace function public.confirm_delivery" "$SQL"
grep -q "create or replace function public.run_delivery_flow_audit_v27" "$SQL"
grep -q "adminRunDeliveryFlowAuditV27" "$REPO"
grep -q "Audit du parcours de livraison V27" "$ADMIN"
grep -q "warning_count" "$SQL"
echo "V27 static checks: OK"
