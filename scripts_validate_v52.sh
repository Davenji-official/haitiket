#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v51.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
repo=(r/'lib/data/repo.dart').read_text()
wallet=(r/'supabase/migrations/0035_financial_release_and_checkout_guards_v26.sql').read_text()
delivery=(r/'supabase/migrations/0036_delivery_flow_hardening_v27.sql').read_text()
orders=(r/'supabase/migrations/0011_variants_tiers_coupons.sql').read_text()
dispute=(r/'supabase/migrations/0031_dispute_financial_integrity.sql').read_text()
refund=(r/'supabase/migrations/0032_wallet_refund_execution.sql').read_text()
official=(r/'supabase/migrations/0042_official_platform_shop_v48.sql').read_text()
readme=(r/'docs/SPRINT_EXTRA_TURBO_V52.md').read_text()
workflow=(r/'.github/workflows/quality-gates.yml').read_text()
checks={
 'external legacy payment entry point fails closed instead of initiating a provider charge': "throw StateError('Ce paiement ($purpose) n’est pas encore migré" in repo,
 'internal order payment uses the server RPC': "_c.rpc('pay_order_from_wallet'" in repo,
 'wallet payment checks the pending-payment state before charging': "o.status <> 'PENDING_PAYMENT'" in wallet and "paid_from_internal_wallet" in wallet,
 'wallet earnings release blocks open disputes': "d.status in ('open','resolved_refund')" in wallet,
 'wallet earnings release blocks active or executed refunds': "r.status in ('to_execute','executed')" in wallet,
 'delivery confirmation requires the delivery PIN and IN_TRANSIT state': 'confirm_delivery(p_job uuid, p_pin text)' in delivery and "o.status <> 'IN_TRANSIT'" in delivery and 'p_pin' in delivery,
 'coupon checkout validates active window and quota server-side': 'active and starts_at <= now()' in orders and '(max_uses is null or used_count < max_uses)' in orders,
 'coupon redemption prevents duplicate user redemption': 'unique (coupon_id, user_id)' in (r/'supabase/migrations/0007_full_features.sql').read_text(),
 'currency remains persisted per order and separate wallet APIs remain distinct': "'currency'" in repo and 'quoteWalletFeeUsd' in repo and 'quoteFee' in repo,
 'official shop remains explicitly typed and active in server logic': "kind='platform'" in official and 'is_official' in official and "status='active'" in official,
 'release gate documentation distinguishes static checks from staging evidence': 'ne constitue pas' in readme and 'staging' in readme.lower() and 'preuve' in readme.lower(),
 'quality workflow invokes V52 validator': './scripts_validate_v52.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V52 static regression gates: OK. This does not replace Flutter, SQL execution, RLS review or live staging tests.')
PYCODE
