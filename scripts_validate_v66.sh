#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
test -s assets/logo.png
grep -q 'adaptive_icon_background' pubspec.yaml
grep -q 'requireApprovedIdentityForBazar' lib/data/repo.dart
grep -q 'Repo.requireApprovedIdentityForBazar' lib/ui/screens7.dart
grep -q 'bazar_requires_approved_kyc' supabase/migrations/0053_bazar_kyc_gate_app_icon_v66.sql
grep -q 'products_require_approved_kyc_for_bazar_v66' supabase/migrations/0053_bazar_kyc_gate_app_icon_v66.sql
grep -q 'V66' docs/SPRINT_EXTRA_TURBO_V66.md
echo 'V66 static checks: PASS'
