#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v45.sh"
python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path
r=Path(sys.argv[1])
ui=(r/'lib/ui/admin2.dart').read_text()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V46.md').read_text()
readme=(r/'README.md').read_text()
checks={
 'audit CSV export is implemented': 'Future<void> exportFilteredCsv(List<Map<String, dynamic>> rows)' in ui,
 'CSV export includes audit metadata columns': all(x in ui for x in ["'Date UTC'", "'Action'", "'Ressource'", "'Acteur'", "'Motif / détail'"]),
 'CSV values are quoted and quote-escaped': "raw.replaceAll('\"', '\"\"')" in ui and "join(',')" in ui,
 'spreadsheet formula prefixes are neutralised': "'=+-@'.contains(trimmed[0])" in ui and "raw = \"'$raw\"" in ui,
 'CSV has UTF-8 BOM and CRLF line endings': "'\\uFEFF$csv'" in ui and "join('\\r\\n')" in ui,
 'export operates on currently filtered rows': 'exportFilteredCsv(rows)' in ui and 'final rows = all.where' in ui,
 'empty exports are disabled': 'onPressed: rows.isEmpty ? null' in ui,
 'quality workflow invokes V46 validator': './scripts_validate_v46.sh' in workflow,
 'documentation notes export scope and limitations': 'maximum 200' in doc and 'staging' in doc.lower() and 'V46' in readme,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V46 static checks: OK. Flutter analyzer/tests and live Supabase verification still require CI/staging.')
PY
