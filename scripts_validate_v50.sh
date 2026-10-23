#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v49.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
ui=(r/'lib/ui/screens2.dart').read_text()
repo=(r/'lib/data/repo.dart').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V50.md').read_text()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'official shop has dedicated overview dashboard': 'Widget _officialShopDashboard()' in ui and 'if (official) _officialShopDashboard()' in ui,
 'dashboard reports catalog, published products and low-stock count': 'Produits au catalogue' in ui and 'Produits publiés' in ui and 'Stock faible (≤ 3)' in ui,
 'low-stock list is limited to five visible entries': 'lowStock.take(5)' in ui and 'À réapprovisionner' in ui,
 'order status counts are derived from loaded orders': 'statusCounts[status] = (statusCounts[status] ?? 0) + 1' in ui and 'État des commandes' in ui,
 'HTG and USD totals remain separate with no conversion': "<String, int>{'HTG': 0, 'USD': 0}" in ui and "money(totals['HTG']!, 'HTG')" in ui and "money(totals['USD']!, 'USD')" in ui,
 'dashboard labels recent order limit and accounting limitation': '50 plus récentes au maximum' in ui and 'ne représentent pas un relevé comptable' in ui,
 'orders source remains limited to at most 50 recent rows': "order('created_at', ascending: false).limit(50)" in repo,
 'V50 doc documents scope and runtime limitations': 'Flutter analyze/test/build' in doc and 'total_minor' in doc and 'staging' in doc.lower(),
 'quality workflow invokes V50 validator': './scripts_validate_v50.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V50 static checks: OK. Flutter and live Supabase staging tests remain required.')
PYCODE
