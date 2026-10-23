#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v37.sh"
test -s "$ROOT/supabase/tests/production_readiness_v38.sql"
test -s "$ROOT/scripts_run_staging_readiness_v38.sh"
test -s "$ROOT/docs/SPRINT_EXTRA_TURBO_V38.md"
test -s "$ROOT/docs/ETAT_DEVELOPPEMENT_HAITIKET_V38.md"
for marker in 'BEGIN READ ONLY' 'has_table_privilege' 'SECURITY DEFINER' 'search_path=' 'has_function_privilege'; do
  grep -Fq "$marker" "$ROOT/supabase/tests/production_readiness_v38.sql" || { echo "V38 SQL contract missing: $marker" >&2; exit 1; }
done
for marker in 'STAGING_ENVIRONMENT' 'ALLOW_STAGING_READONLY_AUDIT' 'STAGING_DATABASE_URL' 'psql'; do
  grep -Fq "$marker" "$ROOT/scripts_run_staging_readiness_v38.sh" || { echo "V38 runner guard missing: $marker" >&2; exit 1; }
done
set +e
env -u STAGING_ENVIRONMENT -u ALLOW_STAGING_READONLY_AUDIT -u STAGING_DATABASE_URL "$ROOT/scripts_run_staging_readiness_v38.sh" >/dev/null 2>&1
rc=$?
set -e
test "$rc" -eq 2 || { echo 'V38 runner must refuse execution without staging guard variables' >&2; exit 1; }
echo 'V38 static checks: OK. SQL audit NOT executed without configured staging database.'
