#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

if [[ "${STAGING_ENVIRONMENT:-}" != "staging" ]]; then
  echo "Refus: définir STAGING_ENVIRONMENT=staging explicitement." >&2
  exit 2
fi
if [[ "${ALLOW_STAGING_READONLY_AUDIT:-}" != "YES" ]]; then
  echo "Refus: confirmer l'audit strictement en lecture seule avec ALLOW_STAGING_READONLY_AUDIT=YES." >&2
  exit 2
fi
if [[ -z "${STAGING_DATABASE_URL:-}" ]]; then
  echo "Refus: STAGING_DATABASE_URL est manquant. Ne jamais publier cette URL ou ses secrets." >&2
  exit 2
fi
if ! command -v psql >/dev/null 2>&1; then
  echo "Erreur: psql n'est pas installé." >&2
  exit 127
fi

# Le SQL contient BEGIN READ ONLY; PGOPTIONS ajoute une seconde barrière.
echo "HAITIKET V40: audit structurel commande/livraison en lecture seule sur staging."
PGOPTIONS="${PGOPTIONS:+${PGOPTIONS} }-c default_transaction_read_only=on" \
  psql "$STAGING_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tests/order_delivery_contract_v40.sql"
echo "V40 PASS: audit SQL terminé. Les scénarios fonctionnels CSV restent à exécuter séparément."
