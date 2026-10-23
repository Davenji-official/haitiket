-- V54: wholesale offers and supplier purchase requests. This is a request workflow, not a payment flow.
alter table public.products add column if not exists wholesale_enabled boolean not null default false;
alter table public.products add column if not exists wholesale_price_minor bigint;
alter table public.products add column if not exists wholesale_min_qty integer not null default 2;
alter table public.products drop constraint if exists products_wholesale_price_nonnegative_v54;
alter table public.products add constraint products_wholesale_price_nonnegative_v54 check (wholesale_price_minor is null or wholesale_price_minor > 0);
alter table public.products drop constraint if exists products_wholesale_min_qty_v54;
alter table public.products add constraint products_wholesale_min_qty_v54 check (wholesale_min_qty between 2 and 10000);
alter table public.products drop constraint if exists products_wholesale_configuration_v54;
alter table public.products add constraint products_wholesale_configuration_v54 check (not wholesale_enabled or wholesale_price_minor is not null);
create index if not exists products_wholesale_catalog_v54 on public.products (created_at desc) where wholesale_enabled and status='published' and stock > 0;

create table if not exists public.wholesale_requests (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  seller_shop_id uuid not null references public.shops(id) on delete restrict,
  buyer_shop_id uuid not null references public.shops(id) on delete restrict,
  product_name text not null,
  seller_shop_name text not null,
  buyer_shop_name text not null,
  quantity integer not null check (quantity between 2 and 10000),
  unit_price_minor bigint not null check (unit_price_minor > 0),
  total_minor bigint generated always as (quantity::bigint * unit_price_minor) stored,
  currency text not null check (currency in ('HTG','USD')),
  status text not null default 'pending' check (status in ('pending','accepted','rejected','cancelled','fulfilled')),
  buyer_note text check (buyer_note is null or char_length(buyer_note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (buyer_shop_id <> seller_shop_id)
);
create index if not exists wholesale_requests_seller_status_v54 on public.wholesale_requests(seller_shop_id,status,created_at desc);
create index if not exists wholesale_requests_buyer_status_v54 on public.wholesale_requests(buyer_shop_id,status,created_at desc);
alter table public.wholesale_requests enable row level security;
drop policy if exists wholesale_requests_participant_read_v54 on public.wholesale_requests;
create policy wholesale_requests_participant_read_v54 on public.wholesale_requests for select to authenticated using (
  exists(select 1 from public.shops s where s.id=buyer_shop_id and s.owner_id=auth.uid())
  or exists(select 1 from public.shops s where s.id=seller_shop_id and s.owner_id=auth.uid())
);

create or replace function public.seller_set_wholesale_offer_v54(p_product uuid, p_enabled boolean, p_price_minor bigint, p_min_qty integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_product public.products%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_min_qty is null or p_min_qty < 2 or p_min_qty > 10000 then raise exception 'wholesale_min_qty_invalid'; end if;
  if p_enabled and (p_price_minor is null or p_price_minor <= 0) then raise exception 'wholesale_price_invalid'; end if;
  select p.* into v_product from public.products p join public.shops s on s.id=p.shop_id
   where p.id=p_product and s.owner_id=auth.uid() and s.status='active' and coalesce(s.kind,'pro') <> 'personal' and not coalesce(s.is_official,false) for update of p;
  if not found then raise exception 'product_not_found_or_shop_not_eligible'; end if;
  if p_enabled and (v_product.status <> 'published' or v_product.stock < p_min_qty) then raise exception 'product_must_be_published_and_have_minimum_stock'; end if;
  update public.products set wholesale_enabled=p_enabled, wholesale_price_minor=case when p_enabled then p_price_minor else null end, wholesale_min_qty=p_min_qty where id=p_product;
  return jsonb_build_object('product_id',p_product,'wholesale_enabled',p_enabled,'wholesale_price_minor',case when p_enabled then p_price_minor else null end,'wholesale_min_qty',p_min_qty);
end $$;
revoke all on function public.seller_set_wholesale_offer_v54(uuid,boolean,bigint,integer) from public,anon;
grant execute on function public.seller_set_wholesale_offer_v54(uuid,boolean,bigint,integer) to authenticated;

create or replace function public.create_wholesale_request_v54(p_product uuid,p_buyer_shop uuid,p_quantity integer,p_note text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_product public.products%rowtype; v_seller public.shops%rowtype; v_buyer public.shops%rowtype; v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_quantity is null or p_quantity < 2 or p_quantity > 10000 then raise exception 'wholesale_quantity_invalid'; end if;
  if char_length(coalesce(p_note,'')) > 500 then raise exception 'wholesale_note_too_long'; end if;
  select * into v_buyer from public.shops where id=p_buyer_shop and owner_id=auth.uid() and status='active' for update;
  if not found then raise exception 'buyer_shop_not_found_or_inactive'; end if;
  select p.* into v_product from public.products p where p.id=p_product for update;
  if not found or v_product.status <> 'published' or not v_product.wholesale_enabled then raise exception 'wholesale_offer_unavailable'; end if;
  select * into v_seller from public.shops where id=v_product.shop_id and status='active';
  if not found then raise exception 'supplier_shop_unavailable'; end if;
  if v_seller.id=v_buyer.id or v_seller.owner_id=auth.uid() then raise exception 'cannot_order_from_own_shop'; end if;
  if p_quantity < v_product.wholesale_min_qty then raise exception 'wholesale_minimum_quantity_not_met'; end if;
  if p_quantity > v_product.stock then raise exception 'wholesale_stock_insufficient'; end if;
  if v_product.wholesale_price_minor is null or v_product.wholesale_price_minor <= 0 then raise exception 'wholesale_price_invalid'; end if;
  insert into public.wholesale_requests(product_id,seller_shop_id,buyer_shop_id,product_name,seller_shop_name,buyer_shop_name,quantity,unit_price_minor,currency,buyer_note)
  values(v_product.id,v_seller.id,v_buyer.id,v_product.name,v_seller.name,v_buyer.name,p_quantity,v_product.wholesale_price_minor,v_product.currency,nullif(btrim(coalesce(p_note,'')),'')) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.create_wholesale_request_v54(uuid,uuid,integer,text) from public,anon;
grant execute on function public.create_wholesale_request_v54(uuid,uuid,integer,text) to authenticated;

create or replace function public.update_wholesale_request_v54(p_request uuid,p_action text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_req public.wholesale_requests%rowtype; v_seller_owner uuid; v_buyer_owner uuid; v_product public.products%rowtype; v_reserved bigint;
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
      select coalesce(sum(quantity),0) into v_reserved from public.wholesale_requests where product_id=v_req.product_id and status='accepted';
      if v_product.id is null or v_product.stock::bigint - v_reserved < v_req.quantity then raise exception 'wholesale_stock_reserved_or_insufficient'; end if;
      update public.wholesale_requests set status='accepted',updated_at=now() where id=p_request returning * into v_req;
    elsif p_action='reject' and v_req.status='pending' then update public.wholesale_requests set status='rejected',updated_at=now() where id=p_request returning * into v_req;
    elsif p_action='fulfill' and v_req.status='accepted' then
      select * into v_product from public.products where id=v_req.product_id for update;
      if v_product.id is null or v_product.stock < v_req.quantity then raise exception 'wholesale_stock_insufficient_at_fulfillment'; end if;
      update public.products set stock=stock-v_req.quantity where id=v_req.product_id;
      update public.wholesale_requests set status='fulfilled',updated_at=now() where id=p_request returning * into v_req;
    else raise exception 'invalid_wholesale_request_transition'; end if;
  elsif p_action='cancel' then
    if v_buyer_owner is distinct from auth.uid() then raise exception 'buyer_shop_not_owned'; end if;
    if v_req.status <> 'pending' then raise exception 'only_pending_request_can_be_cancelled'; end if;
    update public.wholesale_requests set status='cancelled',updated_at=now() where id=p_request returning * into v_req;
  else raise exception 'invalid_wholesale_request_action'; end if;
  return jsonb_build_object('id',v_req.id,'status',v_req.status,'updated_at',v_req.updated_at);
end $$;
revoke all on function public.update_wholesale_request_v54(uuid,text) from public,anon;
grant execute on function public.update_wholesale_request_v54(uuid,text) to authenticated;
