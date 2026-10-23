#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
r=Path(sys.argv[1])
ui=(r/'lib/ui/admin_release_center_v63.dart').read_text()
admin=(r/'lib/ui/admin_screen.dart').read_text()
repo=(r/'lib/data/repo.dart').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V63.md').read_text().lower()
readme=(r/'README.md').read_text().lower()
wf=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'release center widget exists': 'class AdminReleaseCenterV63' in ui,
 'read-only server snapshot used': 'Repo.adminReleaseReadinessV62()' in ui,
 'all operational queues shown': all(k in ui for k in ['refunds_unresolved','kyc_waiting_review','shop_deletions_waiting_or_in_cooling_off','disputed_orders','payment_attempts_refund_required']),
 'JSON report copy is available': 'Clipboard.setData' in ui and 'JsonEncoder.withIndent' in ui,
 'admin navigation has 18 tabs': 'length: 18' in admin and "Tab(text: 'Contrôle lancement')" in admin and 'const AdminReleaseCenterV63()' in admin,
 'repository endpoint already exists': 'adminReleaseReadinessV62' in repo,
 'docs require staging verification': 'tests staging requis' in doc and 'aucun remboursement externe' in doc,
 'README documents V63': 'haitiket v63' in readme,
 'CI invokes V63 validator': 'run: ./scripts_validate_v63.sh' in wf,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V63 static checks: OK; Flutter compilation and Supabase staging tests remain required.')
PY
