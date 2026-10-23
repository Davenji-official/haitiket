#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v53.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
sql=(r/'supabase/migrations/0045_wholesale_supplier_workflow_v54.sql').read_text().lower()
repo=(r/'lib/data/repo.dart').read_text()
ui=(r/'lib/ui/screens2.dart').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V54.md').read_text().lower()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'wholesale fields enforce positive prices and bounded minimum quantity': 'wholesale_price_minor > 0' in sql and 'wholesale_min_qty between 2 and 10000' in sql,
 'only eligible shop owners can configure wholesale offers': 'seller_set_wholesale_offer_v54' in sql and 's.owner_id=auth.uid()' in sql and 's.status=\'active\'' in sql,
 'request workflow stores price/currency and quantity snapshots with bounded notes': 'unit_price_minor,currency,buyer_note' in sql and 'total_minor bigint generated always' in sql and 'wholesale_note_too_long' in sql,
 'buyer must own an active shop and cannot buy from their own shop': 'buyer_shop_not_found_or_inactive' in sql and 'cannot_order_from_own_shop' in sql,
 'supplier request table uses RLS participant reads and no direct write policy': 'enable row level security' in sql and 'wholesale_requests_participant_read_v54' in sql and 'create policy wholesale_requests_participant_read_v54 on public.wholesale_requests for insert' not in sql and 'create policy wholesale_requests_participant_read_v54 on public.wholesale_requests for update' not in sql,
 'acceptance reserves only available stock across accepted requests': 'wholesale_stock_reserved_or_insufficient' in sql and "status='accepted'" in sql and 'for update' in sql,
 'fulfillment decrements stock once under a locked product row': 'update public.products set stock=stock-v_req.quantity' in sql and 'invalid_wholesale_request_transition' in sql,
 'buyer and supplier actions are enforced by server RPC': 'update_wholesale_request_v54' in sql and 'supplier_shop_not_owned' in sql and 'buyer_shop_not_owned' in sql,
 'repository supports offer search and request lifecycle RPCs': 'wholesaleOffers({String query' in repo and 'createWholesaleRequest' in repo and 'updateWholesaleRequest' in repo,
 'professional shop UI configures offers and includes supplier center': 'configureWholesale(p)' in ui and 'WholesaleCenterScreen' in ui and 'Fournisseurs et achats en gros' in ui,
 'UI only exposes actions for the matching buyer or seller shop': 'ownedIds.contains(req[\'seller_shop_id\'].toString())' in ui and 'ownedIds.contains(req[\'buyer_shop_id\'].toString())' in ui,
 'docs disclose no-payment workflow and staging requirements': 'ne déclenche aucun paiement' in doc and 'recette staging requise' in doc,
 'quality workflow runs V54 checks': './scripts_validate_v54.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V54 static checks: OK. Flutter compilation and live Supabase integration tests are still required.')
PYCODE
