#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ "${STAGING_ENVIRONMENT:-}" != "staging" ]]; then echo "Refus: STAGING_ENVIRONMENT=staging requis." >&2; exit 2; fi
if [[ "${ALLOW_STAGING_READONLY_AUDIT:-}" != "YES" ]]; then echo "Refus: ALLOW_STAGING_READONLY_AUDIT=YES requis." >&2; exit 2; fi
if [[ -z "${STAGING_DATABASE_URL:-}" ]]; then echo "Refus: STAGING_DATABASE_URL manquant; ne pas afficher le secret." >&2; exit 2; fi
if ! command -v psql >/dev/null 2>&1; then echo "Erreur: psql n'est pas installé." >&2; exit 127; fi
# URL/identifiants volontairement jamais imprimés. Chaque fichier ouvre une transaction READ ONLY.
echo "HAITIKET V38: exécution des audits structurels en lecture seule sur staging déclaré."
psql "$STAGING_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tests/deployment_inventory_v34.sql"
psql "$STAGING_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tests/financial_staging_gate_v35.sql"
psql "$STAGING_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tests/staging_integrity_v37.sql"
psql "$STAGING_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tests/production_readiness_v38.sql"
echo "V38 PASS: les audits SQL se sont terminés sans erreur. Aucun scénario de paiement n'a été lancé."
