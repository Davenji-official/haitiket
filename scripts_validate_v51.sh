#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v50.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
ui=(r/'lib/ui/screens9.dart').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V51.md').read_text()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'coupon overview summarizes effective, visible, expired and exhausted coupons': all(x in ui for x in ["Résumé des promotions", "Valides : $activeCount", "Visibles : $visibleCount", "Expirées : $expiredCount", "Quota atteint : $exhaustedCount"]),
 'effective coupon state respects active flag, expiry and usage quota': "c['active'] == true && !expired(c) && !exhausted(c)" in ui and "used >= maxUses" in ui and "parsed.isBefore(now)" in ui,
 'coupon rows show effective status and public visibility': "'VALIDE'" in ui and "'EXPIRÉE'" in ui and "'QUOTA ATTEINT'" in ui and "'non affichée publiquement'" in ui,
 'existing server-side coupon activation RPC remains in use': 'Repo.shopSetCouponActive(c[\'id\'] as String, v)' in ui,
 'documentation warns that server-side payment validation is still required': 'côté serveur' in doc and 'staging' in doc.lower() and 'Flutter analyze/test/build' in doc,
 'quality workflow invokes V51 validator': './scripts_validate_v51.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V51 static checks: OK. Flutter and live Supabase staging tests remain required.')
PYCODE
