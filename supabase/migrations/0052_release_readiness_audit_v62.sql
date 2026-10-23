-- V62: read-only operational release readiness snapshot for unlocked administrators.
-- This function reports blockers; it never executes refunds, changes orders, or closes shops.
create or replace function public.admin_release_readiness_v62()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pending_refunds bigint;
  v_stale_refunds bigint;
  v_pending_kyc bigint;
  v_deletion_waiting bigint;
  v_deletion_blocked_refunds bigint;
  v_disputed_orders bigint;
  v_refund_required_payments bigint;
  v_blockers jsonb;
begin
  if not public.admin_unlocked() then
    raise exception 'admin_console_locked';
  end if;

  select count(*) into v_pending_refunds
    from public.refund_requests r where r.status <> 'executed';
  select count(*) into v_stale_refunds
    from public.refund_requests r where r.status <> 'executed'
      and r.created_at < now() - interval '24 hours';
  select count(*) into v_pending_kyc
    from public.identity_verifications iv where iv.status in ('pending','needs_changes');
  select count(*) into v_deletion_waiting
    from public.shops s where s.deletion_review_status in ('pending','approved')
      and s.status <> 'closed';
  select count(*) into v_deletion_blocked_refunds
    from public.shops s
    where s.deletion_review_status = 'approved'
      and exists (select 1 from public.orders o join public.refund_requests r on r.order_id=o.id
                  where o.shop_id=s.id and r.status <> 'executed');
  select count(*) into v_disputed_orders
    from public.orders o where o.status = 'DISPUTED';
  select count(*) into v_refund_required_payments
    from public.payment_attempts p where p.status = 'refund_required';

  v_blockers := jsonb_build_array();
  if v_pending_refunds > 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','refunds_unresolved','count',v_pending_refunds,'severity','critical'));
  end if;
  if v_stale_refunds > 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','refunds_older_than_24h','count',v_stale_refunds,'severity','high'));
  end if;
  if v_disputed_orders > 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','orders_disputed','count',v_disputed_orders,'severity','high'));
  end if;
  if v_refund_required_payments > 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','payments_need_refund_reconciliation','count',v_refund_required_payments,'severity','critical'));
  end if;

  return jsonb_build_object(
    'generated_at', now(),
    'read_only', true,
    'refunds_unresolved', v_pending_refunds,
    'refunds_older_than_24h', v_stale_refunds,
    'kyc_waiting_review', v_pending_kyc,
    'shop_deletions_waiting_or_in_cooling_off', v_deletion_waiting,
    'approved_shop_deletions_blocked_by_refunds', v_deletion_blocked_refunds,
    'disputed_orders', v_disputed_orders,
    'payment_attempts_refund_required', v_refund_required_payments,
    'blockers', v_blockers,
    'note', 'Snapshot is informational. It does not confirm provider-side refunds or authorize production release by itself.'
  );
end;
$$;
revoke all on function public.admin_release_readiness_v62() from public, anon;
grant execute on function public.admin_release_readiness_v62() to authenticated;
comment on function public.admin_release_readiness_v62() is
'Read-only admin release readiness counts for unresolved refunds, KYC, shop deletions and disputed orders; does not mutate operational or financial state.';
