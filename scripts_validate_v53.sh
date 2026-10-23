#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v52.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
repo=(r/'lib/data/repo.dart').read_text()
newprod=(r/'lib/ui/screens7.dart').read_text()
editui=(r/'lib/ui/screens2.dart').read_text()
market=(r/'lib/ui/screens.dart').read_text()
searchpill=(r/'lib/ui/home_screen.dart').read_text()
courier=(r/'lib/ui/screens3.dart').read_text()
share=(r/'lib/ui/product_detail.dart').read_text()
shell=(r/'lib/ui/shell.dart').read_text()
splash=(r/'lib/ui/splash.dart').read_text()
sql=(r/'supabase/migrations/0044_seller_tools_audiences_shop_identity_v53.sql').read_text()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V53.md').read_text()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'professional sellers receive the same stock/order overview dashboard': "if (!personal && !official) _officialShopDashboard()" in editui and 'boutique professionnelle' in editui,
 'new product form allows multiple audience groups': "final Set<String> audiences" in newprod and 'FilterChip(' in newprod and "audiences: audiences.toList()..sort()" in newprod,
 'existing products migrate their legacy single audience into the new array': 'update public.products set audiences = array[audience]' in sql,
 'marketplace filters products by selected audience': "f.contains('audiences', [audience])" in repo and 'audience: audienceFilter' in market,
 'category-specific product forms remain connected to category specs': 'SpecsForm(key: ValueKey(cat![\'id\'])' in newprod and 'specsFor(cat![\'name\'] as String)' in newprod,
 'shop names have normalized database uniqueness': 'shops_name_normalized_unique_v53' in sql and 'duplicate shop names exist' in sql,
 'shop rename, suspension and permanent closure are owner-checked server actions': 'seller_manage_own_shop_v53' in sql and 'owner_id = auth.uid()' in sql and "p_action = 'rename'" in sql and "p_action = 'suspend'" in sql and "p_action = 'close'" in sql,
 'shop search suggestions query active shops and open the matching shop': 'searchShops(String query' in repo and 'Boutiques correspondantes' in market and 'ShopScreen(shop[\'id\'] as String)' in market,
 'product web links can reopen the selected published product': 'Uri.base.queryParameters[\'product\']' in splash and 'Repo.productById(sharedProductId)' in shell and "'product': id" in share,
 'product details provide a direct seller conversation for the selected product': "openChat(context, 'product', p['id'] as String)" in share,
 'courier can withdraw their application and retain history': 'courier_withdraw_self_v53' in sql and 'withdrawCourierRole' in courier and 'status=\'withdrawn\'' in sql,
 'closed shops retain order history and direct deletion is not exposed': "status = 'closed'" in sql and 'historique' in doc.lower() and 'suppression physique' in doc.lower(),
 'docs identify mobile universal-link and live staging limitations': 'liens universels' in doc.lower() and 'staging' in doc.lower() and 'flutter analyze' in doc.lower(),
 'quality workflow invokes V53 validator': './scripts_validate_v53.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V53 static checks: OK. Flutter compilation and live Supabase staging tests are still required.')
PYCODE
