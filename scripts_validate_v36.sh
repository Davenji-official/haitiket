#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v35.sh"
PLAN="$ROOT/docs/SPRINT_EXTRA_TURBO_V36.md"
STATE="$ROOT/docs/ETAT_DEVELOPPEMENT_HAITIKET_V36.md"
test -s "$PLAN"
test -s "$STATE"
for marker in 'W02' 'W03' 'O02' 'D01' 'D03' 'E02' 'R02' 'HTG et USD restent séparés'; do
  grep -Fq "$marker" "$PLAN" || { echo "V36 scenario plan missing: $marker" >&2; exit 1; }
done
for marker in 'présent dans l' 'Plop Plop' 'PENDING_PAYMENT' 'pas' 'GPS'; do
  grep -Fiq "$marker" "$STATE" || { echo "V36 status inventory missing: $marker" >&2; exit 1; }
done
# Source contracts: client legacy external checkout must remain blocked and core RPC wrappers must exist.
grep -Fq 'Aucun paiement externe n’a été lancé.' "$ROOT/lib/data/repo.dart"
grep -Fq "'pay_order_from_wallet'" "$ROOT/lib/data/repo.dart"
grep -Fq 'payBazarListingFromWallet' "$ROOT/lib/data/repo.dart"
grep -Fq 'confirm_pickup' "$ROOT/lib/data/repo.dart"
grep -Fq 'confirm_delivery' "$ROOT/lib/data/repo.dart"
test -s "$ROOT/supabase/functions/plopplop-wallet/index.ts"
test -s "$ROOT/supabase/functions/plopplop-webhook/index.ts"
test -s "$ROOT/supabase/functions/plopplop-withdraw/index.ts"
grep -q 'scripts_validate_v36.sh' "$ROOT/.github/workflows/quality-gates.yml"
echo 'V36 static checks: OK. Financial scenarios documented but NOT executed against staging.'
