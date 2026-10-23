#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v59.sh"
python3 - "$ROOT" <<'PYCODE'
import sys
from pathlib import Path
r=Path(sys.argv[1])
sql=(r/'supabase/migrations/0050_stock_refs_shop_lifecycle_kyc_admin_v60.sql').read_text().lower()
variant=(r/'supabase/migrations/0049_variant_stock_ledger_v59.sql').read_text().lower()
repo=(r/'lib/data/repo.dart').read_text().lower()
ui=(r/'lib/ui/screens2.dart').read_text().lower()
widgets=(r/'lib/ui/widgets.dart').read_text().lower()
doc=(r/'docs/SPRINT_EXTRA_TURBO_V60.md').read_text().lower()
readme=(r/'README.md').read_text().lower()
workflow=(r/'.github/workflows/quality-gates.yml').read_text().lower()
checks={
 'order stock movements receive order references': 'link_stock_ledger_order_v60' in sql and "reference_type='order'" in sql and 'inventory_movements' in sql,
 'supplier handover linked to wholesale request': 'link_wholesale_handover_stock_v60' in sql and "reference_type='supplier_handover'" in sql,
 'stock inflow RPC locks owner product and validates reference': 'seller_record_stock_inflow_v60' in sql and 'for update of p' in sql and 'return_reference_not_eligible' in sql and 'supplier_receipt_reference_not_eligible' in sql,
 'variant stock triggers are split for PostgreSQL compatibility': 'product_variant_stock_insert_v59' in variant and 'product_variant_stock_update_v59' in variant and 'product_variant_stock_delete_v59' in variant,
 'shop deletion has 30-day cooling-off and admin approval': "now()+interval '30 days'" in sql and 'admin_review_shop_deletion_v60' in sql and 'admin_finalize_shop_deletion_v60' in sql,
 'shop suspension/deletion freezes orders and queues refunds idempotently': '_freeze_shop_orders_v60' in sql and 'on conflict(order_id) do nothing' in sql and "'refunds_queued'" in sql,
 'KYC computes age server-side and requires adult/minor-specific documents': 'extract(year from age(current_date,p_dob))' in sql and 'adult_identity_document_required' in sql and 'minor_birth_certificate_and_adult_guardian_documents_required' in sql,
 'KYC private bucket and admin review are present': "values('kyc-private','kyc-private',false" in sql and 'admin_review_identity_verification_v60' in sql and 'admin_unlocked()' in sql,
 'shop activation and courier approval require approved KYC': 'approved_kyc_required_before_shop_activation' in sql and 'approved_kyc_required_before_courier_approval' in sql,
 'admin user ban/unban/soft delete is audited': 'admin_manage_user_v60' in sql and "'soft_delete'" in sql and 'admin_audit_logs' in sql,
 'KYC upload form and admin review tabs are wired in Flutter': 'submitkyc' in (r/'lib/ui/screens.dart').read_text().lower() and 'adminidentityverificationtab' in (r/'lib/ui/admin2.dart').read_text().lower() and 'adminshopdeletiontab' in (r/'lib/ui/admin2.dart').read_text().lower(),
 'repo exposes stock, shop lifecycle, KYC and admin APIs': 'seller_record_stock_inflow_v60' in repo and 'seller_request_shop_deletion_v60' in repo and 'submit_identity_verification_v60' in repo and 'admin_manage_user_v60' in repo,
 'verified badge visually distinct from Bazar': 'boutique vérifiée' in widgets and "final bazar = p['source'] == 'bazar'" in widgets and 'verified_at' in repo,
 'shop close UI explains 30-day administrative review': 'délai minimal de 30 jours' in ui and 'demande envoyée' in ui,
 'concurrency race harness exists for staging': (r/'tests/concurrency/run_variant_stock_race_v60.sh').exists() and 'for update' in sql,
 'documentation describes real refund execution and runtime limitations': 'jamais déclarés exécutés' in doc and 'tests concurrents supabase' in doc,
 'README and CI include V60': 'haitiket v60' in readme and './scripts_validate_v60.sh' in workflow,
}
for label,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+label)
if not all(checks.values()): raise SystemExit(1)
print('V60 static checks: OK. Live SQL, Flutter, concurrency and provider tests are still required.')
PYCODE
