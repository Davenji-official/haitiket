#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v55.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
sql=(r/'supabase/migrations/0047_wholesale_request_history_v56.sql').read_text().lower()
repo=(r/'lib/data/repo.dart').read_text()
ui=(r/'lib/ui/screens2.dart').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V56.md').read_text().lower()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'history captures creation and each major lifecycle transition': "'request_created'" in sql and "'request_accepted'" in sql and "'request_rejected'" in sql and "'request_cancelled'" in sql and "'reservation_expired'" in sql and "'goods_handed_over'" in sql,
 'event records preserve status, quantity, price, total, currency and expiry snapshots': 'old_status,new_status' in sql and 'quantity,unit_price_minor,total_minor,currency,expires_at,actor_id' in sql,
 'events are append-only for authenticated clients': 'enable row level security' in sql and 'for select to authenticated' in sql and ('revoke all on public.wholesale_request_events from public, anon, authenticated' in sql or 'revoke insert, update, delete, truncate' in sql) and 'grant select on public.wholesale_request_events to authenticated' in sql,
 'only owners of buyer or seller shops can read events': 's.owner_id=auth.uid()' in sql and 'seller_shop_id' in sql and 'buyer_shop_id' in sql,
 'trigger runs after request insert or update': 'after insert or update on public.wholesale_requests' in sql and 'execute function public.capture_wholesale_request_event_v56()' in sql,
 'existing requests receive a baseline without fabricated historical transitions': 'backfill a baseline event' in sql and 'where not exists' in sql,
 'repository retrieves only visible, recent events': 'wholesaleRequestEvents({int limit = 200})' in repo and "from('wholesale_request_events')" in repo and '.limit(limit)' in repo,
 'supplier UI shows event type, status transition, total and currency': 'historique des opérations fournisseurs' in ui.lower() and "event['old_status']" in ui and "event['total_minor']" in ui and 'money(event' in ui,
 'documentation explains migration and limitations': '0047_wholesale_request_history_v56.sql' in doc and 'ne peuvent pas être reconstituées' in doc and 'aucun paiement' in doc,
 'quality workflow runs V56 checks': './scripts_validate_v56.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V56 static checks: OK. Flutter compilation and live Supabase integration tests are still required.')
PYCODE
