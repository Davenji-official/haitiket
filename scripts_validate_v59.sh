#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v58.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
sql=(r/'supabase/migrations/0049_variant_stock_ledger_v59.sql').read_text().lower()
repo=(r/'lib/data/repo.dart').read_text()
ui=(r/'lib/ui/screens2.dart').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V59.md').read_text().lower()
readme=(r/'README.md').read_text().lower()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'variant movements include variant and business reference columns': 'add column if not exists variant_id' in sql and 'reference_type' in sql and 'reference_id' in sql,
 'variant stock changes are captured by a database trigger': 'capture_variant_stock_movement_v59' in sql and 'product_variant_stock_movement_v59' in sql,
 'variant adjustment RPC validates owner, bounds and reservations': 'seller_adjust_variant_stock_v59' in sql and 's.owner_id=auth.uid()' in sql and 'stock_cannot_be_negative' in sql and 'stock_below_reserved_wholesale_quantity' in sql,
 'repository calls the secure variant adjustment RPC': 'adjustvariantstock' in repo.lower() and 'seller_adjust_variant_stock_v59' in repo,
 'inventory UI exposes individual variant adjustments': '_adjustvariant' in ui.lower() and 'ajuster la variante' in ui.lower(),
 'documentation states duplicate aggregate/variant and reference limitations': 'deux niveaux différents' in doc and 'pas encore automatiquement remplies' in doc,
 'README documents V59': 'haitiket v59' in readme and 'product_variants.stock' in readme,
 'quality workflow runs V59 checks': './scripts_validate_v59.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V59 static checks: OK. Flutter compilation and live Supabase integration tests remain required.')
PYCODE
