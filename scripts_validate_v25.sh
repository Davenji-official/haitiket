#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

grep -q "pushReplacement(MaterialPageRoute<void>(builder: (_) => const OrdersScreen()))" lib/ui/screens2.dart
grep -q "Repo.payOrderFromWallet(orderId)" lib/ui/screens2.dart
grep -q "final Set<String> payingOrders" lib/ui/screens2.dart
grep -q "run_financial_reconciliation_v24" supabase/migrations/0034_financial_reconciliation_v24.sql
grep -q "mutations_performed', false" supabase/migrations/0034_financial_reconciliation_v24.sql
test -f docs/SPRINT_EXTRA_TURBO_V25_CHECKOUT.md
if grep -RniE "functions\.invoke\(['\"]bazik-pay|/bazik-pay|Repo\.startPayment\(" lib; then
  echo "ERREUR: appel direct à un ancien paiement externe détecté dans lib/" >&2
  exit 1
fi
echo "V25 static checks: OK (does not replace Flutter compilation or Supabase integration tests)."
