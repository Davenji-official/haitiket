#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v56.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
ui=(r/'lib/ui/screens2.dart').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V57.md').read_text().lower()
readme=(r/'README.md').read_text().lower()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'supplier history has 7/30/90 day filters': "historyDays = 30" in ui and "DropdownMenuItem(value: 7" in ui and "DropdownMenuItem(value: 30" in ui and "DropdownMenuItem(value: 90" in ui,
 'supplier history can filter event type': "historyType == 'all' || event['event_type'] == historyType" in ui and "DropdownMenuItem(value: 'goods_handed_over'" in ui,
 'date filter operates on parsed UTC timestamps': "DateTime.tryParse('${event['created_at'] ?? ''}')?.toUtc()" in ui and 'subtract(Duration(days: historyDays))' in ui,
 'report shows HTG and USD separately and disclaims accounting revenue': "'HTG': 0, 'USD': 0" in ui and 'pas un chiffre d’affaires ni une preuve de paiement' in ui,
 'CSV includes event and request details': "'Date UTC', 'ID demande', 'Événement'" in ui and "e['unit_price_minor']" in ui and "e['total_minor']" in ui,
 'CSV escapes quotes and neutralizes spreadsheet formulas': "'=+-@'.contains(trimmed[0])" in ui and "raw.replaceAll('\\\"', '\\\"\\\"')" in ui,
 'CSV export copies UTF-8 BOM to clipboard': "Clipboard.setData(ClipboardData(text: '\\uFEFF$csv'))" in ui,
 'documentation notes maximum 200 loaded events and no payment proof': '200 événements les plus récents' in doc and 'ni une preuve de paiement' in doc,
 'README documents V57 limitations': 'haitiket v57' in readme and '200 événements' in readme,
 'quality workflow runs V57 checks': './scripts_validate_v57.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V57 static checks: OK. Flutter compilation and live Supabase integration tests remain required.')
PYCODE
