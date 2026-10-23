#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v34.sh"
SQL="$ROOT/supabase/tests/financial_staging_gate_v35.sql"
test -s "$SQL"
test -s "$ROOT/scripts_run_staging_financial_gates_v35.sh"
test -s "$ROOT/docs/SPRINT_EXTRA_TURBO_V35.md"
for marker in \
  'V35 PASS: required tables are present' \
  'RLS enabled on wallet tables' \
  'SECURITY DEFINER and pinned search_path' \
  'wallet_provider_tx_unique' \
  'V35 STRUCTURAL GATE PASSED'; do
  grep -Fq "$marker" "$SQL" || { echo "V35 SQL gate missing: $marker" >&2; exit 1; }
done
# Ensure SQL gate does not mutate business data or schema.
if grep -niE '^[[:space:]]*(insert|update|delete|truncate|alter|drop|create|grant|revoke)[[:space:]]' "$SQL"; then
  echo 'V35 SQL gate must remain read-only.' >&2; exit 1
fi
grep -q 'HAITIKET_ENV' "$ROOT/scripts_run_staging_financial_gates_v35.sh"
grep -q 'financial_staging_gate_v35.sql' "$ROOT/scripts_run_staging_financial_gates_v35.sh"
grep -q 'scripts_validate_v35.sh' "$ROOT/.github/workflows/quality-gates.yml"
grep -q 'scripts_validate_v35.sh' "$ROOT/docs/SPRINT_EXTRA_TURBO_V35.md"
echo 'V35 static gates: OK. Staging SQL, real provider transactions and Flutter CI still require their respective environments.'
