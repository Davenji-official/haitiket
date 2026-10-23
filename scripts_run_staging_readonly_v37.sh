#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

# Guard rails: this runner is intentionally limited to read-only structural audits.
if [[ "${STAGING_ENVIRONMENT:-}" != "staging" ]]; then
  echo "Refus: définir STAGING_ENVIRONMENT=staging explicitement." >&2
  exit 2
fi
if [[ "${ALLOW_STAGING_READONLY_AUDIT:-}" != "YES" ]]; then
  echo "Refus: confirmer l'audit en lecture seule avec ALLOW_STAGING_READONLY_AUDIT=YES." >&2
  exit 2
fi
if [[ -z "${STAGING_DATABASE_URL:-}" ]]; then
  echo "Refus: STAGING_DATABASE_URL est manquant (ne pas coller le secret dans un rapport)." >&2
  exit 2
fi
if ! command -v psql >/dev/null 2>&1; then
  echo "Erreur: psql n'est pas installé dans cet environnement." >&2
  exit 127
fi

# Do not print the database URL or credentials.
echo "HAITIKET V37: audits SQL structurels en lecture seule sur l'environnement déclaré staging."
psql "$STAGING_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tests/deployment_inventory_v34.sql"
psql "$STAGING_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tests/financial_staging_gate_v35.sql"
psql "$STAGING_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tests/staging_integrity_v37.sql"
echo "V37 PASS: les trois scripts SQL se sont terminés sans erreur. Vérifier et archiver les sorties; aucun paiement réel n'a été lancé."
