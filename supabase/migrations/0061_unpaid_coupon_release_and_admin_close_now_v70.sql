-- HAITIKET 0061 : (1) une réservation non payée libère aussi son code promo, (2) l'administration peut fermer une boutique
-- IMMÉDIATEMENT (sans attendre les 30 jours), tout en traitant les commandes en cours. Ré-exécutable sans risque.

begin;

-- ---------- 1) Annulation d'une réservation non payée : stock + code promo remis ----------
create or replace function public._cancel_order(p_order uuid, p_actor uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; v_coupon uuid;
begin
  select * into o from public.orders where id = p_order for update;
  if o.id is null or o.status <> 'PENDING_PAYMENT' then return; end if;
  perform public._restore_stock(p_order, p_reason, p_actor);
  update public.orders set status = 'CANCELLED', reserved_until = null where id = p_order;
  insert into public.order_status_events(order_id, from_status, to_status, actor, reason)
    values (p_order, 'PENDING_PAYMENT', 'CANCELLED', p_actor, p_reason);
  -- le code promo consommé par cette réservation non payée redevient utilisable
  delete from public.coupon_redemptions where order_id = p_order returning coupon_id into v_coupon;
  if v_coupon is not null then
    update public.coupons set used_count = greatest(used_count - 1, 0) where id = v_coupon;
  end if;
end $$;

-- ---------- 2) Fermeture immédiate d'une boutique par l'administration ----------
create or replace function public.admin_close_shop_now_v70(p_shop uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.shops%rowtype;
  v_review jsonb;
  v_refunds integer;
  v_inflight integer;
begin
  if not public.admin_unlocked() then raise exception 'admin_console_locked'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'admin_reason_required'; end if;

  select * into s from public.shops where id = p_shop for update;
  if not found then raise exception 'shop_not_found'; end if;
  if coalesce(s.is_official, false) or coalesce(s.kind, 'pro') = 'platform' then raise exception 'official_shop_managed_by_admin'; end if;
  if s.status = 'closed' then
    return jsonb_build_object('shop_id', p_shop, 'closed', true, 'already_closed', true);
  end if;

  -- Passe par la procédure normale (annule les commandes en cours, met les remboursements en file), sans délai d'attente.
  if coalesce(s.deletion_review_status, 'none') <> 'approved' then
    if coalesce(s.deletion_review_status, 'none') <> 'pending_admin' then
      update public.shops set deletion_review_status = 'pending_admin', deletion_requested_at = coalesce(deletion_requested_at, now()) where id = p_shop;
    end if;
    v_review := public.admin_review_shop_deletion_v60(p_shop, true, p_reason);
  end if;

  update public.shops set deletion_scheduled_at = now() where id = p_shop;

  select count(*) into v_inflight from public.orders
   where shop_id = p_shop and status not in ('CANCELLED', 'REFUNDED', 'COMPLETED', 'DELIVERED');
  select count(*) into v_refunds from public.orders o join public.refund_requests r on r.order_id = o.id
   where o.shop_id = p_shop and r.status <> 'executed';

  if v_inflight > 0 or v_refunds > 0 then
    -- On ne ferme pas tant qu'un client attend encore un remboursement : la boutique reste suspendue (invisible, sans nouvelle vente).
    insert into public.admin_audit_logs(actor, action, resource, resource_id, reason)
      values (auth.uid(), 'shop_close_now_pending_refunds', 'shop', p_shop, left(p_reason, 200));
    return jsonb_build_object('shop_id', p_shop, 'closed', false, 'unresolved_refunds', v_refunds, 'inflight_orders', v_inflight);
  end if;

  update public.shops set status = 'closed', deletion_review_status = 'completed', deletion_scheduled_at = now() where id = p_shop;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason)
    values (auth.uid(), 'shop_closed_immediately', 'shop', p_shop, left(p_reason, 200));
  return jsonb_build_object('shop_id', p_shop, 'closed', true, 'unresolved_refunds', 0, 'inflight_orders', 0);
end;
$$;
revoke all on function public.admin_close_shop_now_v70(uuid, text) from public, anon;
grant execute on function public.admin_close_shop_now_v70(uuid, text) to authenticated;

commit;

notify pgrst, 'reload schema';
