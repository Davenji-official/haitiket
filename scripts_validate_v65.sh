#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
python3 -m unittest discover -s tests/release -p 'test_*.py' -v
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
r=Path(sys.argv[1])
checks=[
 ('V64 release acceptance script present',(r/'scripts_validate_v64.sh').is_file()),
 ('V65 executable contract tests present',(r/'tests/release/test_release_contract_v65.py').is_file()),
 ('variant concurrency test is explicitly staging-only','disposable supabase staging' in (r/'tests/concurrency/run_variant_stock_race_v60.sh').read_text().lower()),
 ('README documents V65','v65' in (r/'README.md').read_text().lower()),
]
for name,ok in checks: print(('OK' if ok else 'FAIL')+': '+name)
if not all(ok for _,ok in checks): raise SystemExit(1)
print('V65 checks passed. Source-contract tests are not live database integration tests.')
PY
bash -n "$ROOT/scripts_validate_v65.sh"
