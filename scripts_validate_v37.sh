#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v36.sh"
test -s "$ROOT/supabase/tests/staging_integrity_v37.sql"
test -s "$ROOT/scripts_run_staging_readonly_v37.sh"
test -s "$ROOT/docs/SPRINT_EXTRA_TURBO_V37.md"
test -s "$ROOT/docs/ETAT_DEVELOPPEMENT_HAITIKET_V37.md"
test -s "$ROOT/docs/RECETTE_STAGING_V37.csv"
for marker in 'BEGIN READ ONLY' 'wallet_provider_tx_unique' 'confirm_pickup' 'confirm_delivery' 'admin_execute_wallet_refund'; do
  grep -Fq "$marker" "$ROOT/supabase/tests/staging_integrity_v37.sql" || { echo "V37 SQL contract missing: $marker" >&2; exit 1; }
done
for marker in 'STAGING_ENVIRONMENT' 'ALLOW_STAGING_READONLY_AUDIT' 'STAGING_DATABASE_URL' 'psql'; do
  grep -Fq "$marker" "$ROOT/scripts_run_staging_readonly_v37.sh" || { echo "V37 runner guard missing: $marker" >&2; exit 1; }
done
grep -Fq 'scripts_validate_v37.sh' "$ROOT/.github/workflows/quality-gates.yml"
# Prove the staging runner refuses to start unless explicitly configured.
set +e
env -u STAGING_ENVIRONMENT -u ALLOW_STAGING_READONLY_AUDIT -u STAGING_DATABASE_URL \
  "$ROOT/scripts_run_staging_readonly_v37.sh" >/dev/null 2>&1
rc=$?
set -e
test "$rc" -eq 2 || { echo 'V37 runner must refuse execution without staging guard variables' >&2; exit 1; }
echo 'V37 static checks: OK. SQL staging runner NOT executed without a configured staging database.'
