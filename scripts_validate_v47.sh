#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v46.sh"
python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path
r=Path(sys.argv[1])
repo=(r/'lib/data/repo.dart').read_text()
ui=(r/'lib/ui/admin2.dart').read_text()
sql=(r/'supabase/migrations/0041_admin_order_history_v47.sql').read_text()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V47.md').read_text()
checks={
 'repository calls the V47 history RPC': "admin_order_history_v47" in repo and "'p_days': days" in repo and "'p_currency': currency" in repo,
 'history UI has 7, 30, and 90 day filters': '[7, 30, 90]' in ui,
 'history UI keeps currencies separated': "const ['HTG', 'USD']" in ui and "row['currency'] == cur" in ui,
 'history UI has order and paid amount charts': "'order_count'" in sql and "'paid_total_minor'" in sql and "Nombre de commandes" in ui,
 'server enforces authenticated unlocked admin': "auth.uid() is null or not public.admin_unlocked()" in sql,
 'server restricts period and currency': 'least(coalesce(p_days, 30), 90)' in sql and "('ALL', 'HTG', 'USD')" in sql,
 'history RPC is read-only aggregate': 'returns jsonb' in sql and 'insert into' not in sql.lower() and 'update public.' not in sql.lower() and 'delete from' not in sql.lower(),
 'RPC grants authenticated only': 'revoke all on function public.admin_order_history_v47(integer, text) from public, anon' in sql and 'to authenticated' in sql,
 'quality workflow runs V47 validator': './scripts_validate_v47.sh' in workflow,
 'documentation states staging/runtime limitations': 'staging' in doc.lower() and 'Flutter' in doc and 'HTG' in doc and 'USD' in doc,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V47 static checks: OK. Apply migration in staging and run Flutter/SQL integration tests before production.')
PY
