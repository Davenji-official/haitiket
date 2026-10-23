#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v61.sh"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
r=Path(sys.argv[1])
sql=(r/'supabase/migrations/0052_release_readiness_audit_v62.sql').read_text().lower()
repo=(r/'lib/data/repo.dart').read_text().lower()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V62.md').read_text().lower()
readme=(r/'README.md').read_text().lower()
wf=(r/'.github/workflows/quality-gates.yml').read_text().lower()
checks={
 'release snapshot is admin-locked': 'admin_release_readiness_v62' in sql and 'admin_unlocked()' in sql and 'admin_console_locked' in sql,
 'snapshot is read-only and covers unresolved refunds': "'read_only', true" in sql and 'refunds_unresolved' in sql and "r.status <> 'executed'" in sql,
 'snapshot reports old refunds and payment reconciliation': 'refunds_older_than_24h' in sql and 'payment_attempts_refund_required' in sql,
 'snapshot includes KYC, deletion and dispute queues': 'kyc_waiting_review' in sql and 'shop_deletions_waiting_or_in_cooling_off' in sql and 'disputed_orders' in sql,
 'RPC grants authenticated only, not public/anon': 'revoke all on function public.admin_release_readiness_v62() from public, anon' in sql and 'to authenticated' in sql,
 'Dart repository wrapper exists': 'adminreleasereadinessv62' in repo,
 'docs clearly state no financial mutation or provider confirmation': 'strictement en lecture seule' in doc and 'ne marque aucun remboursement comme exécuté' in doc and 'prestataire' in doc,
 'README documents V62': 'haitiket v62' in readme,
 'CI invokes V62 validator': './scripts_validate_v62.sh' in wf,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V62 static checks: OK; staging SQL and Flutter validation remain required.')
PY
