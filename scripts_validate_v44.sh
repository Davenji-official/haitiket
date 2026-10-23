#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v43.sh"
python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path
r=Path(sys.argv[1])
admin=(r/'lib/ui/admin2.dart').read_text()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V44.md').read_text()
checks={
 'dashboard CSV export button': "Exporter les statistiques (CSV)" in admin,
 'CSV export uses current dashboard data': 'exportDashboardCsv(d)' in admin,
 'CSV export is copied through platform clipboard': 'Clipboard.setData(ClipboardData(text:' in admin,
 'CSV values escaped for quotes': 'replaceAll' in admin and '""' in admin,
 'quality workflow invokes V44 validator': './scripts_validate_v44.sh' in workflow,
 'documentation distinguishes implemented and unverified': 'Flutter' in doc and 'production' in doc.lower(),
}
for name,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+name)
failed=[name for name,ok in checks.items() if not ok]
if failed: raise SystemExit(1)
print('V44 static checks: OK. Flutter analysis/tests and live Supabase verification remain required.')
PY
