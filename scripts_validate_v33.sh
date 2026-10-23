#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v32.sh"
test -s "$ROOT/supabase/tests/financial_regression_v33.sql"
for marker in \
  "public.pay_order_from_wallet(uuid)" \
  "public.confirm_wallet_topup(text,text,bigint)" \
  "public.finish_wallet_withdrawal(text,boolean,text,bigint)" \
  "wallet_provider_tx_unique" \
  "RLS disabled on wallet_transactions" \
  "V33 REGRESSION CONTRACT OK"; do
  grep -Fq "$marker" "$ROOT/supabase/tests/financial_regression_v33.sql" || {
    echo "V33 regression contract missing expected check: $marker" >&2; exit 1;
  }
done
if grep -nE '^[[:space:]]*(insert|update|delete|truncate|alter|drop|create)[[:space:]]' "$ROOT/supabase/tests/financial_regression_v33.sql"; then
  echo 'V33 regression contract must remain read-only.' >&2; exit 1
fi
test -s "$ROOT/docs/SPRINT_EXTRA_TURBO_V33.md"
grep -q 'financial_regression_v33.sql' "$ROOT/docs/SPRINT_EXTRA_TURBO_V33.md"
grep -Eq 'scripts_validate_v(33|34|35).sh' "$ROOT/.github/workflows/quality-gates.yml"
echo 'V33 static gates: OK. Database regression contract, Flutter build and end-to-end provider tests still require staging/CI.'
