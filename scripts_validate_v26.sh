#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SQL="$ROOT/supabase/migrations/0035_financial_release_and_checkout_guards_v26.sql"
test -s "$SQL"
grep -q "create or replace function public.pay_order_from_wallet" "$SQL"
grep -q "create or replace function public._release_order_wallet_earnings" "$SQL"
grep -q "old.status='DISPUTED'" "$SQL"
grep -q "run_financial_guard_audit_v26" "$SQL"
grep -q "adminRunFinancialGuardAuditV26" "$ROOT/lib/data/repo.dart"
grep -q "Audit des garde-fous financiers V26" "$ROOT/lib/ui/admin2.dart"
echo "V26 static checks: OK"
echo "Note: this script does not compile Flutter or execute SQL against Supabase."
