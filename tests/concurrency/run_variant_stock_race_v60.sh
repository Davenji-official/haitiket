#!/usr/bin/env bash
# Destructive integration test: use only a disposable Supabase STAGING variant with stock=1.
set -euo pipefail
: "${DATABASE_URL:?Set DATABASE_URL to a disposable staging database}"
: "${TEST_USER_ID:?Set TEST_USER_ID to the owner of the variant's active professional shop}"
: "${TEST_VARIANT_ID:?Set TEST_VARIANT_ID to a variant whose stock is exactly 1}"
command -v psql >/dev/null || { echo 'psql is required' >&2; exit 2; }
initial=$(psql "$DATABASE_URL" -XAtqc "select stock from public.product_variants where id='${TEST_VARIANT_ID}'::uuid")
if [[ "$initial" != "1" ]]; then echo "Fixture must start at stock=1; found: $initial" >&2; exit 2; fi
race_call() {
  psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -qAt <<SQL
begin;
select set_config('request.jwt.claim.sub','${TEST_USER_ID}',true);
select public.seller_adjust_variant_stock_v59('${TEST_VARIANT_ID}'::uuid,-1,'V60 concurrency race test');
select pg_sleep(2);
commit;
SQL
}
set +e
race_call > /tmp/htk_v60_race_a.log 2>&1 & a=$!
race_call > /tmp/htk_v60_race_b.log 2>&1 & b=$!
wait "$a"; ra=$?
wait "$b"; rb=$?
set -e
successes=0
[[ $ra -eq 0 ]] && successes=$((successes+1))
[[ $rb -eq 0 ]] && successes=$((successes+1))
stock=$(psql "$DATABASE_URL" -XAtqc "select stock from public.product_variants where id='${TEST_VARIANT_ID}'::uuid")
# Restore fixture after measuring result; a single successful decrement should leave zero.
if [[ "$successes" -eq 1 && "$stock" == "0" ]]; then
  psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -qAt <<SQL
select set_config('request.jwt.claim.sub','${TEST_USER_ID}',false);
select public.seller_adjust_variant_stock_v59('${TEST_VARIANT_ID}'::uuid,1,'Restore V60 concurrency fixture');
SQL
  echo 'PASS: exactly one concurrent decrement succeeded; stock never went negative; fixture restored.'
  exit 0
fi
echo "FAIL: successes=$successes final_stock=$stock" >&2
cat /tmp/htk_v60_race_a.log /tmp/htk_v60_race_b.log >&2
exit 1
