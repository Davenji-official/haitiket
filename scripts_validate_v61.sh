#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v60.sh"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
r=Path(sys.argv[1]); sql=(r/'supabase/migrations/0051_shop_reactivation_safety_v61.sql').read_text().lower()
repo=(r/'lib/data/repo.dart').read_text().lower(); readme=(r/'README.md').read_text().lower(); doc=(r/'docs/SPRINT_EXTRA_TURBO_V61.md').read_text().lower(); wf=(r/'.github/workflows/quality-gates.yml').read_text().lower()
checks={
 'rejected deletion cannot silently reactivate shop': "new.deletion_review_status='rejected'" in sql and "new.status:='suspended'" in sql,
 'reactivation is explicit and owner-scoped': 'seller_reactivate_shop_v61' in sql and 'owner_id=auth.uid()' in sql,
 'reactivation requires approved KYC': 'approved_kyc_required_before_shop_reactivation' in sql,
 'reactivation blocks unresolved refunds': 'shop_has_unresolved_refunds' in sql and "r.status<>'executed'" in sql,
 'reactivation resets deletion lifecycle fields': 'deletion_review_status=\'none\'' in sql and 'deletion_scheduled_at=null' in sql,
 'reactivation is auditable': 'seller_shop_reactivated' in sql and 'admin_audit_logs' in sql,
 'repo exposes explicit reactivation': 'seller_reactivate_shop_v61' in repo,
 'README documents V61': 'haitiket v61' in readme,
 'CI invokes V61 validator': './scripts_validate_v61.sh' in wf,
 'documentation states runtime limitations': 'staging' in doc and 'production' in doc,
}
for k,v in checks.items(): print(('OK' if v else 'FAIL')+': '+k)
if not all(checks.values()): raise SystemExit(1)
print('V61 static checks: OK; live migration and Flutter tests remain required.')
PY
