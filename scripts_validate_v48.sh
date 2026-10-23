#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v47.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
repo=(r/'lib/data/repo.dart').read_text()
admin=(r/'lib/ui/admin_screen.dart').read_text()
widgets=(r/'lib/ui/widgets.dart').read_text()
sql=(r/'supabase/migrations/0042_official_platform_shop_v48.sql').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V48.md').read_text()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'admin has dedicated official shop tab': "Tab(text: 'Boutique officielle')" in admin and 'length: 17' in admin and 'const OfficialShopAdminTab()' in admin,
 'official shop is created/updated only by unlocked admin RPC': 'admin_save_official_shop' in repo and 'admin_unlocked()' in sql and 'admin_save_official_shop' in sql,
 'official shop is unique and marked platform-owned': 'shops_single_official_idx' in sql and "'platform',true,'Boutique officielle HAITIKET'" in sql,
 'official shop bypasses seller subscription only': "kind = 'personal' or is_official or plan_paid_until > now()" in sql,
 'official store panel exempts official shop from subscription UI': "if (!personal && !official) PlanCard(shop: widget.shop)" in (r/'lib/ui/screens2.dart').read_text(),
 'official products use Marketplace and show badge': 'shops(id,name,lat,lng,kind,is_official,official_badge_label,verified_at)' in repo and 'Boutique officielle HAITIKET' in widgets and "source: personal ? 'bazar' : 'marketplace'" in (r/'lib/ui/screens2.dart').read_text(),
 'official shop branding supports admin-only platform store': "kind in ('pro','platform')" in sql and 'is_official and public.admin_unlocked()' in sql,
 'official shop products and orders are scoped to unlocked admin': 'products_write' in sql and 'orders_official_admin_read' in sql and 's.is_official and public.admin_unlocked()' in sql,
 'admin changes are audit logged': "'create_official_shop'" in sql and "'update_official_shop'" in sql,
 'migration documented and staging cautions present': 'staging' in doc.lower() and 'Flutter' in doc and '0042_official_platform_shop_v48.sql' in doc,
 'quality workflow invokes V48 validator': './scripts_validate_v48.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V48 static checks: OK. Flutter and live Supabase staging tests remain required.')
PYCODE
