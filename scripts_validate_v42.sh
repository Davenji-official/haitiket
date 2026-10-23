#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v41.sh"
"$ROOT/scripts_validate_release_assets.sh"
python3 - "$ROOT/.github/workflows/build.yml" "$ROOT/.github/workflows/quality-gates.yml" <<'PY'
import sys
from pathlib import Path
build=Path(sys.argv[1]).read_text()
quality=Path(sys.argv[2]).read_text()
if 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB' in build:
    raise SystemExit('V42 FAIL: transparent 1x1 logo fallback still permits a broken release')
if build.count('./scripts_validate_release_assets.sh') != 2:
    raise SystemExit('V42 FAIL: release asset validation must run in both Web and Android jobs')
if build.count('dart run flutter_launcher_icons') != 2:
    raise SystemExit('V42 FAIL: icon generation must be a blocking step in both build jobs')
if '|| echo "Icônes ignorées"' in build:
    raise SystemExit('V42 FAIL: icon generation failures must not be swallowed')
if './scripts_validate_v42.sh' not in quality:
    raise SystemExit('V42 FAIL: quality workflow is not running this validator')
print('V42 CI hardening checks: OK')
PY
echo 'V42 static checks: OK. Actual Flutter builds and provider/database staging tests still require CI/staging execution.'
