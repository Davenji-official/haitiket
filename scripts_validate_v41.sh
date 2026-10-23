#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v40.sh"
BUILD="$ROOT/.github/workflows/build.yml"
QUALITY="$ROOT/.github/workflows/quality-gates.yml"
test -s "$BUILD"
test -s "$QUALITY"
test -s "$ROOT/docs/SPRINT_EXTRA_TURBO_V41.md"
test -s "$ROOT/docs/ETAT_DEVELOPPEMENT_HAITIKET_V41.md"
test -s "$ROOT/docs/qa/RELEASE_GATE_V41.md"
# Both build jobs must run tests before their respective build command.
python3 - "$BUILD" <<'PY'
import sys
from pathlib import Path
s=Path(sys.argv[1]).read_text()
if s.count('run: flutter test') != 2:
    raise SystemExit('V41 FAIL: expected exactly two blocking flutter test steps (Web and Android)')
web_start=s.find('  web:\n')
android_start=s.find('  android:\n')
if web_start < 0 or android_start < 0 or android_start <= web_start:
    raise SystemExit('V41 FAIL: expected Web and Android jobs')
blocks={
  'Web': s[web_start:android_start],
  'Android': s[android_start:]
}
for job, block, build_marker in [('Web', blocks['Web'], 'flutter build web --release'), ('Android', blocks['Android'], 'flutter build apk --release')]:
    test_at=block.find('run: flutter test')
    build_at=block.find(build_marker)
    if test_at < 0 or build_at < 0 or test_at > build_at:
        raise SystemExit(f'V41 FAIL: tests must run before {build_marker} in {job}')
print('V41 CI order checks: OK')
PY
grep -Fq './scripts_validate_v41.sh' "$QUALITY" || { echo 'V41 workflow hook missing' >&2; exit 1; }
grep -Fq 'NOT_RUN' "$ROOT/docs/qa/RELEASE_GATE_V41.md"
grep -Fq 'Plop Plop' "$ROOT/docs/qa/RELEASE_GATE_V41.md"
echo 'V41 static checks: OK. Flutter tests/builds and live Supabase/provider flows still require CI/staging execution.'
