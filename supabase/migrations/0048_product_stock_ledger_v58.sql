-- V58: traceable inventory ledger and owner-authorized stock adjustments.
-- Records stock changes made by product updates. Does not mutate wallets or orders.
create table if not exists public.product_stock_movements (
  id bigint generated always as identity primary key,
  product_id uuid not null references public.products(id) on delete restrict,
  shop_id uuid not null references public.shops(id) on delete restrict,
  movement_type text not null check (movement_type in ('initial_stock','stock_change','manual_adjustment')),
  old_stock integer,
  new_stock integer not null check (new_stock >= 0),
  quantity_delta integer not null,
  reason text not null default 'Mise à jour du stock' check (char_length(reason) between 1 and 240),
  actor_id uuid,
  created_at timestamptz not null default now(),
  check (old_stock is null or old_stock >= 0),
  check (quantity_delta <> 0)
);
create index if not exists product_stock_movements_shop_time_v58
  on public.product_stock_movements(shop_id, created_at desc, id desc);
create index if not exists product_stock_movements_product_time_v58
  on public.product_stock_movements(product_id, created_at desc, id desc);

alter table public.product_stock_movements enable row level security;
drop policy if exists product_stock_movements_owner_read_v58 on public.product_stock_movements;
create policy product_stock_movements_owner_read_v58
  on public.product_stock_movements for select to authenticated
  using (exists(select 1 from public.shops s where s.id=product_stock_movements.shop_id and s.owner_id=auth.uid()));
revoke all on public.product_stock_movements from public, anon, authenticated;
grant select on public.product_stock_movements to authenticated;
revoke all on sequence public.product_stock_movements_id_seq from public, anon, authenticated;

create or replace function public.capture_product_stock_movement_v58()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_reason text;
  v_type text;
  v_old integer;
  v_delta integer;
begin
  if tg_op = 'INSERT' then
    v_old := null;
    v_delta := coalesce(new.stock, 0);
    if v_delta <= 0 then return new; end if;
    v_type := 'initial_stock';
    v_reason := 'Stock initial enregistré';
  else
    if new.stock is not distinct from old.stock then return new; end if;
    v_old := old.stock;
    v_delta := new.stock - old.stock;
    v_type := 'stock_change';
    v_reason := nullif(left(coalesce(current_setting('haitiket.stock_reason', true), ''), 240), '');
    if v_reason is null then v_reason := 'Mise à jour du stock'; end if;
    if current_setting('haitiket.stock_manual', true) = 'true' then v_type := 'manual_adjustment'; end if;
  end if;
  insert into public.product_stock_movements(product_id,shop_id,movement_type,old_stock,new_stock,quantity_delta,reason,actor_id)
  values(new.id,new.shop_id,v_type,v_old,new.stock,v_delta,v_reason,auth.uid());
  return new;
end $$;
revoke all on function public.capture_product_stock_movement_v58() from public, anon, authenticated;
drop trigger if exists product_stock_movement_insert_v58 on public.products;
drop trigger if exists product_stock_movement_update_v58 on public.products;
create trigger product_stock_movement_insert_v58 after insert on public.products
for each row execute function public.capture_product_stock_movement_v58();
create trigger product_stock_movement_update_v58 after update of stock on public.products
for each row execute function public.capture_product_stock_movement_v58();

create or replace function public.seller_adjust_product_stock_v58(p_product uuid, p_delta integer, p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_product public.products%rowtype;
  v_new_stock bigint;
  v_reserved bigint;
  v_reason text;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_delta is null or p_delta = 0 or abs(p_delta::bigint) > 100000 then raise exception 'stock_delta_invalid'; end if;
  v_reason := btrim(coalesce(p_reason,''));
  if char_length(v_reason) < 3 or char_length(v_reason) > 240 then raise exception 'stock_reason_invalid'; end if;
  select p.* into v_product from public.products p join public.shops s on s.id=p.shop_id
   where p.id=p_product and s.owner_id=auth.uid() and s.status='active' and coalesce(s.kind,'pro') <> 'personal'
   for update of p;
  if not found then raise exception 'product_not_found_or_shop_not_eligible'; end if;
  v_new_stock := v_product.stock::bigint + p_delta::bigint;
  if v_new_stock < 0 then raise exception 'stock_cannot_be_negative'; end if;
  if v_new_stock > 2147483647 then raise exception 'stock_limit_exceeded'; end if;
  if p_delta < 0 then
    select coalesce(sum(r.quantity),0) into v_reserved
      from public.wholesale_requests r
     where r.product_id=p_product and r.status='accepted'
       and (r.expires_at is null or r.expires_at > now());
    if v_new_stock < v_reserved then raise exception 'stock_below_reserved_wholesale_quantity'; end if;
  end if;
  perform set_config('haitiket.stock_reason', v_reason, true);
  perform set_config('haitiket.stock_manual', 'true', true);
  update public.products set stock=v_new_stock::integer where id=p_product;
  return jsonb_build_object('product_id',p_product,'old_stock',v_product.stock,'new_stock',v_new_stock,'delta',p_delta);
end $$;
revoke all on function public.seller_adjust_product_stock_v58(uuid,integer,text) from public, anon;
grant execute on function public.seller_adjust_product_stock_v58(uuid,integer,text) to authenticated;

-- Baseline current inventory for products that existed before the ledger.
insert into public.product_stock_movements(product_id,shop_id,movement_type,old_stock,new_stock,quantity_delta,reason,actor_id,created_at)
select p.id,p.shop_id,'initial_stock',null,p.stock,p.stock,'Stock de référence à l’installation V58',null,now()
from public.products p
where p.stock > 0
  and not exists(select 1 from public.product_stock_movements m where m.product_id=p.id);
