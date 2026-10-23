#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v48.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
repo=(r/'lib/data/repo.dart').read_text()
ui=(r/'lib/ui/screens2.dart').read_text()
widgets=(r/'lib/ui/widgets.dart').read_text()
sql=(r/'supabase/migrations/0043_official_shop_merchandising_v49.sql').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V49.md').read_text()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'featured field loaded by catalog and shop management': 'is_featured' in repo and "order('is_featured', ascending: false)" in repo,
 'official shop product management has featured toggle': 'adminSetOfficialProductFeatured' in ui and "if (official)" in ui and "Icons.star_border" in ui,
 'featured official products show storefront badge': "p['is_featured'] == true" in widgets and "'À la une'" in widgets,
 'database field defaults false and has catalog index': 'add column if not exists is_featured boolean not null default false' in sql and 'products_featured_catalog_idx' in sql,
 'server requires unlocked admin and restricts official active platform shop': 'not public.admin_unlocked()' in sql and 's.is_official and s.kind = \'platform\' and s.status = \'active\'' in sql,
 'server RPC is authenticated-only and audit logged': 'revoke all on function public.admin_set_official_product_featured_v49(uuid, boolean) from public, anon' in sql and 'to authenticated' in sql and 'admin_audit_logs' in sql,
 'documentation explains staging and runtime test limitations': 'staging' in doc.lower() and 'Flutter' in doc and 'RLS' in doc,
 'quality workflow invokes V49 validator': './scripts_validate_v49.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V49 static checks: OK. Flutter and live Supabase staging tests remain required.')
PYCODE
