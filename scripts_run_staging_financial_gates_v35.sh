#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ "${HAITIKET_ENV:-}" != "staging" ]]; then
  echo 'Refus de lancer : définis HAITIKET_ENV=staging explicitement.' >&2
  exit 2
fi
if [[ -z "${STAGING_DATABASE_URL:-}" ]]; then
  echo 'STAGING_DATABASE_URL est requis; ne partage pas cette URL ni ses secrets.' >&2
  exit 2
fi
if ! command -v psql >/dev/null 2>&1; then
  echo 'psql est requis sur la machine qui exécute ce script.' >&2
  exit 2
fi
OUT="${HAITIKET_REPORT_FILE:-$ROOT/financial-staging-v35-report.txt}"
: > "$OUT"
for sql in \
  supabase/tests/financial_preflight_v32.sql \
  supabase/tests/financial_regression_v33.sql \
  supabase/tests/deployment_inventory_v34.sql \
  supabase/tests/financial_staging_gate_v35.sql; do
  echo "===== $sql =====" | tee -a "$OUT"
  psql "$STAGING_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$ROOT/$sql" 2>&1 | tee -a "$OUT"
done
echo "Rapport écrit dans : $OUT"
echo 'Attention : ce rapport vérifie le schéma et les permissions observables, pas les parcours de paiement réels.'
