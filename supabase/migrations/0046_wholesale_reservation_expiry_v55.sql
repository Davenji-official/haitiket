-- V55: bound accepted wholesale reservations and safely release abandoned requests.
-- This migration does not add payment capture or automatic supplier payments.
alter table public.wholesale_requests
  add column if not exists expires_at timestamptz;

-- Give existing accepted requests a finite reservation window from their last update.
update public.wholesale_requests
   set expires_at = coalesce(updated_at, created_at, now()) + interval '7 days'
 where status = 'accepted' and expires_at is null;

alter table public.wholesale_requests drop constraint if exists wholesale_requests_status_check;
alter table public.wholesale_requests add constraint wholesale_requests_status_check
  check (status in ('pending','accepted','rejected','cancelled','expired','fulfilled'));

create index if not exists wholesale_requests_expiry_v55
  on public.wholesale_requests (expires_at)
  where status = 'accepted' and expires_at is not null;

create or replace function public.update_wholesale_request_v54(p_request uuid,p_action text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_req public.wholesale_requests%rowtype;
  v_seller_owner uuid;
  v_buyer_owner uuid;
  v_product public.products%rowtype;
  v_reserved bigint;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into v_req from public.wholesale_requests where id=p_request for update;
  if not found then raise exception 'wholesale_request_not_found'; end if;
  select owner_id into v_seller_owner from public.shops where id=v_req.seller_shop_id;
  select owner_id into v_buyer_owner from public.shops where id=v_req.buyer_shop_id;

  if p_action in ('accept','reject','fulfill') then
    if v_seller_owner is distinct from auth.uid() then raise exception 'supplier_shop_not_owned'; end if;
    if p_action='accept' and v_req.status='pending' then
      select * into v_product from public.products where id=v_req.product_id for update;
      select coalesce(sum(quantity),0) into v_reserved
        from public.wholesale_requests where product_id=v_req.product_id and status='accepted'
          and (expires_at is null or expires_at > now());
      if v_product.id is null or v_product.stock::bigint - v_reserved < v_req.quantity then
        raise exception 'wholesale_stock_reserved_or_insufficient';
      end if;
      update public.wholesale_requests
         set status='accepted', expires_at=now()+interval '7 days', updated_at=now()
       where id=p_request returning * into v_req;
    elsif p_action='reject' and v_req.status='pending' then
      update public.wholesale_requests set status='rejected',expires_at=null,updated_at=now()
       where id=p_request returning * into v_req;
    elsif p_action='fulfill' and v_req.status='accepted' then
      if v_req.expires_at is not null and v_req.expires_at <= now() then
        update public.wholesale_requests set status='expired',updated_at=now()
         where id=p_request returning * into v_req;
        return jsonb_build_object('id',v_req.id,'status',v_req.status,'updated_at',v_req.updated_at,'message','reservation_expired_stock_released');
      end if;
      select * into v_product from public.products where id=v_req.product_id for update;
      if v_product.id is null or v_product.stock < v_req.quantity then raise exception 'wholesale_stock_insufficient_at_fulfillment'; end if;
      update public.products set stock=stock-v_req.quantity where id=v_req.product_id;
      update public.wholesale_requests set status='fulfilled',expires_at=null,updated_at=now()
       where id=p_request returning * into v_req;
    else
      raise exception 'invalid_wholesale_request_transition';
    end if;
  elsif p_action='cancel' then
    if v_buyer_owner is distinct from auth.uid() then raise exception 'buyer_shop_not_owned'; end if;
    if v_req.status not in ('pending','accepted') then raise exception 'only_pending_or_accepted_request_can_be_cancelled'; end if;
    update public.wholesale_requests set status='cancelled',expires_at=null,updated_at=now()
     where id=p_request returning * into v_req;
  else
    raise exception 'invalid_wholesale_request_action';
  end if;
  return jsonb_build_object('id',v_req.id,'status',v_req.status,'expires_at',v_req.expires_at,'updated_at',v_req.updated_at);
end $$;
revoke all on function public.update_wholesale_request_v54(uuid,text) from public,anon;
grant execute on function public.update_wholesale_request_v54(uuid,text) to authenticated;

-- Intended for a scheduled job or an operator with service_role. Safe to run repeatedly.
create or replace function public.expire_wholesale_reservations_v55()
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;
begin
  update public.wholesale_requests
     set status='expired', expires_at=null, updated_at=now()
   where status='accepted' and expires_at is not null and expires_at <= now();
  get diagnostics v_count = row_count;
  return v_count;
end $$;
revoke all on function public.expire_wholesale_reservations_v55() from public,anon,authenticated;
grant execute on function public.expire_wholesale_reservations_v55() to service_role;
