#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v44.sh"
python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path
r=Path(sys.argv[1])
sql=(r/'supabase/migrations/0040_admin_audit_log_v45.sql').read_text().lower()
repo=(r/'lib/data/repo.dart').read_text()
admin=(r/'lib/ui/admin_screen.dart').read_text()
ui=(r/'lib/ui/admin2.dart').read_text()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V45.md').read_text()
checks={
 'audit reader migration exists': 'create or replace function public.admin_read_audit_log' in sql,
 'audit reader requires unlocked admin': 'not public.admin_unlocked()' in sql,
 'audit reader is read-only and bounded': 'from public.admin_audit_logs l' in sql and 'least(coalesce(p_take, 100), 200)' in sql and 'security definer' in sql,
 'anon cannot execute audit reader': 'from public, anon' in sql,
 'repository calls audit RPC': "rpc('admin_read_audit_log'" in repo,
 'admin tab registered': "Tab(text: 'Journal admin')" in admin and 'AdminAuditLogTab()' in admin,
 'audit UI has filter and refresh': 'Filtrer action, ressource' in ui and 'onPressed: reload' in ui,
 'quality workflow invokes V45': './scripts_validate_v45.sh' in workflow,
 'docs note staging limitations': 'staging' in doc.lower() and 'NOT_RUN' in doc,
}
for name, ok in checks.items(): print(('OK' if ok else 'FAIL') + ': ' + name)
if not all(checks.values()): raise SystemExit(1)
print('V45 static checks: OK. Flutter tests/builds and live Supabase permissions remain to be verified in CI/staging.')
PY
