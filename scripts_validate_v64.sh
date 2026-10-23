#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
r=Path(sys.argv[1])
checks=[]
def has(path,*needles):
    p=r/path
    if not p.exists(): return False
    s=p.read_text(errors='replace').lower()
    return all(n.lower() in s for n in needles)
# Release acceptance contract: verify the actual code paths and explicit operational boundaries.
checks += [
 ('V63 admin release center remains wired', has('lib/ui/admin_release_center_v63.dart','adminReleaseReadinessV62','refunds_unresolved','kyc_waiting_review')),
 ('V62 audit remains server-side and read-only', has('supabase/migrations/0052_release_readiness_audit_v62.sql','admin_release_readiness_v62','read_only','refunds_unresolved')),
 ('V60 stock ledger references order events', has('supabase/migrations/0050_stock_refs_shop_lifecycle_kyc_admin_v60.sql','link_stock_ledger_order_v60','reference_type=\'order\'','inventory_movements')),
 ('V60 stock ledger references supplier handovers', has('supabase/migrations/0050_stock_refs_shop_lifecycle_kyc_admin_v60.sql','link_wholesale_handover_stock_v60','supplier_handover')),
 ('V60 lifecycle queues refunds instead of claiming execution', has('supabase/migrations/0050_stock_refs_shop_lifecycle_kyc_admin_v60.sql','refund','queue')),
 ('V61 reactivation checks outstanding refunds and KYC', has('supabase/migrations/0051_shop_reactivation_safety_v61.sql','kyc','refund','reactivat')),
 ('V58 stock adjustment is bounded and transactional', has('supabase/migrations/0048_product_stock_ledger_v58.sql','for update','seller_adjust_product_stock_v58','stock_below_reserved_wholesale_quantity')),
 ('CI has Flutter analyze and test jobs', has('.github/workflows/quality-gates.yml','flutter analyze','flutter test')),
 ('V64 acceptance documentation defines staging tests', has('docs/SPRINT_EXTRA_TURBO_V64.md','staging','simultanés','remboursement','flutter test')),
 ('README documents V64', has('README.md','haitiket v64')),
]
failed=False
for label,ok in checks:
 print(('OK' if ok else 'FAIL')+': '+label)
 failed |= not ok
if failed: raise SystemExit(1)
print('V64 release acceptance contract: OK. This is static verification, not proof of runtime behavior.')
PY
bash -n "$ROOT/scripts_validate_v64.sh"
