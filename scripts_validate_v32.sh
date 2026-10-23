#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Preserve all previous static quality gates.
test -x "$ROOT/scripts_validate_v31.sh"
"$ROOT/scripts_validate_v31.sh"

# Require the staging-only financial preflight and its documented invariants.
test -s "$ROOT/supabase/tests/financial_preflight_v32.sql"
for marker in \
  "public.pay_order_from_wallet(uuid)" \
  "public.admin_execute_wallet_refund(uuid,text)" \
  "SECURITY DEFINER" \
  "has_function_privilege('anon'" \
  "V32 PREFLIGHT OK"; do
  grep -Fq "$marker" "$ROOT/supabase/tests/financial_preflight_v32.sql" || {
    echo "V32 preflight missing expected check: $marker" >&2; exit 1;
  }
done

# Verify this is read-only test SQL: disallow common DML/DDL statement starts.
if grep -nE '^[[:space:]]*(insert|update|delete|truncate|alter|drop|create)[[:space:]]' \
  "$ROOT/supabase/tests/financial_preflight_v32.sql"; then
  echo 'V32 preflight must remain read-only.' >&2; exit 1
fi

test -s "$ROOT/docs/SPRINT_EXTRA_TURBO_V32.md"
grep -q 'financial_preflight_v32.sql' "$ROOT/docs/SPRINT_EXTRA_TURBO_V32.md"
grep -Eq 'scripts_validate_v(32|33|34|35)\.sh' "$ROOT/.github/workflows/quality-gates.yml"
echo 'V32 static gates: OK. Live staging preflight, Flutter build and end-to-end money-flow tests remain to be run.'
