"""Executable static contract tests. These inspect source contracts; they do not replace PostgreSQL integration tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

def source(path):
    return (ROOT / path).read_text(encoding='utf-8').lower()

class ReleaseContractV65(unittest.TestCase):
    def test_stock_adjustment_is_transactional_and_bounded(self):
        sql = source('supabase/migrations/0048_product_stock_ledger_v58.sql')
        self.assertIn('seller_adjust_product_stock_v58', sql)
        self.assertIn('for update', sql)
        self.assertIn('stock_below_reserved_wholesale_quantity', sql)
        self.assertIn('grant execute', sql)

    def test_variant_race_test_is_staging_guarded(self):
        script = source('tests/concurrency/run_variant_stock_race_v60.sh')
        self.assertIn('database_url', script)
        self.assertIn('test_variant_id', script)
        self.assertIn('stock=1', script)
        self.assertIn('successes', script)
        self.assertIn('stock never went negative', script)

    def test_shop_deletion_has_admin_review_and_cooling_off(self):
        sql = source('supabase/migrations/0050_stock_refs_shop_lifecycle_kyc_admin_v60.sql')
        self.assertIn('admin_review_shop_deletion_v60', sql)
        self.assertIn('admin_finalize_shop_deletion_v60', sql)
        self.assertIn('shop_deletion_cooling_off_period_active', sql)
        self.assertIn('30 days', sql)
        self.assertIn('_freeze_shop_orders_v60', sql)

    def test_reactivation_requires_safety_checks(self):
        sql = source('supabase/migrations/0051_shop_reactivation_safety_v61.sql')
        self.assertIn('seller_reactivate_shop_v61', sql)
        self.assertIn('kyc', sql)
        self.assertIn('refund', sql)

    def test_kyc_review_is_admin_gated_and_audited(self):
        sql = source('supabase/migrations/0050_stock_refs_shop_lifecycle_kyc_admin_v60.sql')
        self.assertIn('admin_review_identity_verification_v60', sql)
        self.assertIn('admin_audit_logs', sql)
        self.assertIn('identity_verifications', sql)

    def test_release_readiness_is_read_only_report(self):
        sql = source('supabase/migrations/0052_release_readiness_audit_v62.sql')
        self.assertIn('admin_release_readiness_v62', sql)
        self.assertIn('refunds_unresolved', sql)
        self.assertIn('kyc_waiting_review', sql)
        self.assertIn('shop_deletions_waiting_or_in_cooling_off', sql)

    def test_ci_contains_runtime_flutter_tests(self):
        workflow = source('.github/workflows/quality-gates.yml')
        self.assertIn('flutter analyze', workflow)
        self.assertIn('flutter test', workflow)

if __name__ == '__main__':
    unittest.main(verbosity=2)
