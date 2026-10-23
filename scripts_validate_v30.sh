#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# 1) Run each existing sprint's static checks.
for script in scripts_validate_v25.sh scripts_validate_v26.sh scripts_validate_v27.sh scripts_validate_v28.sh scripts_validate_v29.sh; do
  test -x "$ROOT/$script" || { echo "Missing or non-executable validator: $script" >&2; exit 1; }
  "$ROOT/$script"
done

# 2) Check that numbered migrations are present and sequential.
mapfile -t versions < <(find "$ROOT/supabase/migrations" -maxdepth 1 -type f -printf '%f\n' \
  | grep -E '^[0-9]{4}_.+\.sql$' | sed -E 's/^([0-9]{4})_.*/\1/' | sort -n)
[ "${#versions[@]}" -gt 0 ] || { echo "No numbered SQL migrations found" >&2; exit 1; }
expected=1
for version in "${versions[@]}"; do
  actual=$((10#$version))
  if [ "$actual" -ne "$expected" ]; then
    printf 'Migration sequence gap/duplicate: expected %04d, found %s\n' "$expected" "$version" >&2
    exit 1
  fi
  expected=$((expected + 1))
done

# 3) Ensure the latest launch audit migration and wiring exist.
test -s "$ROOT/supabase/migrations/0038_launch_readiness_audit_v29.sql"
grep -q 'run_launch_readiness_audit_v29' "$ROOT/lib/data/repo.dart"
grep -q 'Audit global de préparation au lancement V29' "$ROOT/lib/ui/admin2.dart"

# 4) Prevent common private credential names from being committed into client code.
if grep -RInE '(SUPABASE_SERVICE_ROLE_KEY|PLOPPLOP_CLIENT_SECRET|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)' \
    "$ROOT/lib" --include='*.dart'; then
  echo 'Potential server-side secret reference found in Flutter client code.' >&2
  exit 1
fi

echo 'V30 quality gates: OK (static checks only; no Flutter build or live database test implied).'
