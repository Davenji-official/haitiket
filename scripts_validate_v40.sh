#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v39.sh"
for f in \
  "$ROOT/supabase/tests/order_delivery_contract_v40.sql" \
  "$ROOT/scripts_run_order_delivery_contract_v40.sh" \
  "$ROOT/docs/SPRINT_EXTRA_TURBO_V40.md" \
  "$ROOT/docs/ETAT_DEVELOPPEMENT_HAITIKET_V40.md" \
  "$ROOT/docs/qa/order_delivery_matrix_v40.csv"; do
  test -s "$f" || { echo "V40 artifact missing: $f" >&2; exit 1; }
done
for marker in 'BEGIN READ ONLY' 'SECURITY DEFINER' 'search_path=' 'seller_set_order_status' 'confirm_pickup' 'confirm_delivery'; do
  grep -Fq "$marker" "$ROOT/supabase/tests/order_delivery_contract_v40.sql" || { echo "V40 SQL marker missing: $marker" >&2; exit 1; }
done
for marker in 'STAGING_ENVIRONMENT' 'ALLOW_STAGING_READONLY_AUDIT' 'STAGING_DATABASE_URL' 'default_transaction_read_only=on' 'psql'; do
  grep -Fq "$marker" "$ROOT/scripts_run_order_delivery_contract_v40.sh" || { echo "V40 runner guard missing: $marker" >&2; exit 1; }
done
for marker in 'ORD-102' 'DEL-103' 'DEL-105' 'FIN-102' 'NOT_RUN'; do
  grep -Fq "$marker" "$ROOT/docs/qa/order_delivery_matrix_v40.csv" || { echo "V40 scenario missing: $marker" >&2; exit 1; }
done
set +e
env -u STAGING_ENVIRONMENT -u ALLOW_STAGING_READONLY_AUDIT -u STAGING_DATABASE_URL "$ROOT/scripts_run_order_delivery_contract_v40.sh" >/dev/null 2>&1
rc=$?
set -e
test "$rc" -eq 2 || { echo 'V40 runner must refuse execution without explicit staging guards' >&2; exit 1; }
# The workflow must include the new validator.
grep -Fq './scripts_validate_v40.sh' "$ROOT/.github/workflows/quality-gates.yml" || { echo 'V40 workflow hook missing' >&2; exit 1; }
echo 'V40 static checks: OK. SQL audit NOT executed without configured staging database.'
