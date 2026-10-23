#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v33.sh"
SQL="$ROOT/supabase/tests/deployment_inventory_v34.sql"
test -s "$SQL"
test -s "$ROOT/docs/SPRINT_EXTRA_TURBO_V34.md"
for marker in \
  'supabase_migrations.schema_migrations' \
  'wallet_accounts' \
  'wallet_transactions' \
  'security_definer' \
  'trigger_definition' \
  'READ-ONLY INVENTORY COMPLETE'; do
  grep -Fq "$marker" "$SQL" || { echo "V34 inventory missing: $marker" >&2; exit 1; }
done
# Keep this diagnostic script strictly read-only; allow SELECT, DO and psql meta-commands only.
if grep -niE '^[[:space:]]*(insert|update|delete|truncate|alter|drop|create|grant|revoke)[[:space:]]' "$SQL"; then
  echo 'V34 inventory must remain read-only.' >&2; exit 1
fi
# The Flutter application must not invoke the retired Bazik checkout endpoints.
if grep -RniE 'functions\.invoke\([^\n]*(bazik-pay|bazik-webhook)|/functions/v1/(bazik-pay|bazik-webhook)' "$ROOT/lib" --include='*.dart'; then
  echo 'Legacy Bazik checkout invocation found in Flutter source.' >&2; exit 1
fi
# Ensure the intended provider functions are present in this archive.
for f in plopplop-wallet plopplop-webhook plopplop-withdraw; do
  test -s "$ROOT/supabase/functions/$f/index.ts" || { echo "Missing Plop Plop function: $f" >&2; exit 1; }
done
grep -Eq 'scripts_validate_v(34|35).sh' "$ROOT/.github/workflows/quality-gates.yml"
grep -q 'deployment_inventory_v34.sql' "$ROOT/docs/SPRINT_EXTRA_TURBO_V34.md"
echo 'V34 static gates: OK. Live Supabase inventory, deployed Edge Function inventory and provider/webhook verification still require authorized staging access.'
