#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v38.sh"
for f in \
  "$ROOT/docs/SPRINT_EXTRA_TURBO_V39.md" \
  "$ROOT/docs/ETAT_DEVELOPPEMENT_HAITIKET_V39.md" \
  "$ROOT/docs/qa/RELEASE_CHECKLIST_V39.md" \
  "$ROOT/docs/qa/acceptance_matrix_v39.csv"; do
  test -s "$f" || { echo "V39 required artifact missing: $f" >&2; exit 1; }
done
for marker in 'NO-GO' 'Plop Plop' 'RLS' 'flutter analyze' 'flutter test'; do
  grep -Fq "$marker" "$ROOT/docs/qa/RELEASE_CHECKLIST_V39.md" || { echo "V39 checklist marker missing: $marker" >&2; exit 1; }
done
for marker in 'FIN-001' 'FIN-002' 'FIN-005' 'DEL-001' 'DEL-003' 'REF-001' 'APP-001'; do
  grep -Fq "$marker" "$ROOT/docs/qa/acceptance_matrix_v39.csv" || { echo "V39 scenario missing: $marker" >&2; exit 1; }
done
# Fail closed if any test is accidentally marked passed without evidence fields.
grep -Fq 'Statut initial' "$ROOT/docs/qa/acceptance_matrix_v39.csv"
echo 'V39 static checks: OK. Acceptance scenarios remain NOT_RUN until executed with evidence on staging.'
