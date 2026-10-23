#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Preserve the earlier static gates.
test -x "$ROOT/scripts_validate_v30.sh"
"$ROOT/scripts_validate_v30.sh"

# Require the new test suite and CI workflow wiring.
test -s "$ROOT/test/i18n_test.dart"
test -s "$ROOT/test/config_test.dart"
test -s "$ROOT/.github/workflows/quality-gates.yml"
grep -q "known strings are translated into Haitian Creole" "$ROOT/test/i18n_test.dart"
grep -q "unknown strings fall back to the French source string" "$ROOT/test/i18n_test.dart"
grep -q "flutter test" "$ROOT/.github/workflows/quality-gates.yml"
grep -q "flutter analyze" "$ROOT/.github/workflows/quality-gates.yml"

# Check all numbered migrations are sequential (static naming check only).
mapfile -t versions < <(find "$ROOT/supabase/migrations" -maxdepth 1 -type f -printf '%f\n' \
  | grep -E '^[0-9]{4}_.+\.sql$' | sed -E 's/^([0-9]{4})_.*/\1/' | sort -n)
[ "${#versions[@]}" -gt 0 ] || { echo 'No numbered migrations found' >&2; exit 1; }
expected=1
for version in "${versions[@]}"; do
  actual=$((10#$version))
  [ "$actual" -eq "$expected" ] || { printf 'Migration gap/duplicate: expected %04d, found %s\n' "$expected" "$version" >&2; exit 1; }
  expected=$((expected + 1))
done

echo 'V31 static gates: OK. Flutter tests/build and live Supabase remain unverified until CI/staging runs.'
