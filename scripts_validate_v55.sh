#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v54.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
sql=(r/'supabase/migrations/0046_wholesale_reservation_expiry_v55.sql').read_text().lower()
repo=(r/'lib/data/repo.dart').read_text()
ui=(r/'lib/ui/screens2.dart').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V55.md').read_text().lower()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'accepted requests receive a finite seven-day expiry': "expires_at=now()+interval '7 days'" in sql and 'add column if not exists expires_at' in sql,
 'legacy accepted requests receive an expiry': "where status = 'accepted' and expires_at is null" in sql,
 'expired status is supported': "'expired'" in sql and 'wholesale_requests_status_check' in sql,
 'buyer can cancel pending or accepted requests and release reservations': "v_req.status not in ('pending','accepted')" in sql and "set status='cancelled',expires_at=null" in sql,
 'fulfillment after expiry releases the reservation instead of decrementing stock': 'reservation_expired_stock_released' in sql and "set status='expired'" in sql,
 'scheduled cleanup is repeatable and service-role-only': 'expire_wholesale_reservations_v55' in sql and 'to service_role' in sql and 'from public,anon,authenticated' in sql,
 'repository reads reservation expiry': "updated_at,expires_at" in repo,
 'supplier center shows expiry and lets buyer cancel accepted requests': "req['expires_at']" in ui and "req['status'] == 'accepted')) IconButton" in ui,
 'docs require a trusted scheduler and staging concurrency tests': 'service_role' in doc and 'deux demandes concurrentes' in doc and 'aucun paiement' in doc,
 'quality workflow runs V55 checks': './scripts_validate_v55.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V55 static checks: OK. Flutter compilation and live Supabase integration tests are still required.')
PYCODE
