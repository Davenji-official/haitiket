#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v57.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
sql=(r/'supabase/migrations/0048_product_stock_ledger_v58.sql').read_text().lower()
repo=(r/'lib/data/repo.dart').read_text()
ui=(r/'lib/ui/screens2.dart').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V58.md').read_text().lower()
readme=(r/'README.md').read_text().lower()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'stock ledger table and movement indexes exist': 'create table if not exists public.product_stock_movements' in sql and 'product_stock_movements_shop_time_v58' in sql and 'product_stock_movements_product_time_v58' in sql,
 'stock mutations are captured by database triggers': 'create trigger product_stock_movement_insert_v58' in sql and 'create trigger product_stock_movement_update_v58' in sql and 'capture_product_stock_movement_v58' in sql,
 'ledger is owner-readable and direct writes are revoked': 'product_stock_movements_owner_read_v58' in sql and 'revoke all on public.product_stock_movements from public, anon, authenticated' in sql and 'grant select on public.product_stock_movements to authenticated' in sql,
 'adjustment RPC validates owner, non-negative stock and wholesale reservations': 'seller_adjust_product_stock_v58' in sql and 's.owner_id=auth.uid()' in sql and 'stock_cannot_be_negative' in sql and 'stock_reason_invalid' in sql and 'stock_below_reserved_wholesale_quantity' in sql,
 'repo reads ledger and calls adjustment RPC': 'static future<list<map<string, dynamic>>> stockmovements' in repo.lower() and 'seller_adjust_product_stock_v58' in repo,
 'UI exposes inventory screen and reason-required adjustments': 'class stockledgerscreen' in ui.lower() and 'motif obligatoire' in ui.lower() and 'ouvrir l’inventaire et le journal de stock' in ui.lower(),
 'documentation explains variant and historical limits': 'product_variants.stock' in doc and 'sans inventer les mouvements passés' in doc,
 'README documents V58': 'haitiket v58' in readme and 'product_stock_movements' in readme,
 'quality workflow runs V58 checks': './scripts_validate_v58.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V58 static checks: OK. Flutter compilation and live Supabase integration tests remain required.')
PYCODE
