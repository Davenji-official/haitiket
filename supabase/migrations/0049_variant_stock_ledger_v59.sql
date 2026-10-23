-- V59: stock traceability for size/color variants. Product aggregate movements remain
-- recorded by V58's products trigger; variant rows identify the exact SKU/option.
alter table public.product_stock_movements
  add column if not exists variant_id uuid references public.product_variants(id) on delete restrict;
alter table public.product_stock_movements
  add column if not exists reference_type text,
  add column if not exists reference_id uuid;
create index if not exists product_stock_movements_variant_time_v59
  on public.product_stock_movements(variant_id, created_at desc, id desc) where variant_id is not null;

create or replace function public.capture_variant_stock_movement_v59()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_product public.products%rowtype;
  v_old integer;
  v_delta integer;
  v_reason text;
  v_type text;
begin
  if tg_op = 'DELETE' then
    select p.* into v_product from public.products p where p.id=old.product_id;
    v_old := old.stock; v_delta := -old.stock;
    if v_delta = 0 then return old; end if;
    v_reason := 'Suppression de variante';
    insert into public.product_stock_movements(product_id,shop_id,variant_id,movement_type,old_stock,new_stock,quantity_delta,reason,actor_id)
    values(v_product.id,v_product.shop_id,old.id,'stock_change',v_old,0,v_delta,v_reason,auth.uid());
    return old;
  end if;
  select p.* into v_product from public.products p where p.id=new.product_id;
  if tg_op = 'INSERT' then
    v_old := null; v_delta := new.stock; v_type := 'initial_stock'; v_reason := 'Stock initial de variante';
  else
    if new.stock is not distinct from old.stock then return new; end if;
    v_old := old.stock; v_delta := new.stock-old.stock; v_type := 'stock_change';
    v_reason := nullif(left(coalesce(current_setting('haitiket.stock_reason',true),''),240),'');
    if v_reason is null then v_reason := 'Mise à jour du stock de variante'; end if;
    if current_setting('haitiket.stock_manual',true)='true' then v_type := 'manual_adjustment'; end if;
  end if;
  if v_delta <> 0 then
    insert into public.product_stock_movements(product_id,shop_id,variant_id,movement_type,old_stock,new_stock,quantity_delta,reason,actor_id,reference_type,reference_id)
    values(v_product.id,v_product.shop_id,new.id,v_type,v_old,new.stock,v_delta,v_reason,auth.uid(),
      nullif(current_setting('haitiket.stock_reference_type',true),''),
      nullif(current_setting('haitiket.stock_reference_id',true),'')::uuid);
  end if;
  return new;
end $$;
revoke all on function public.capture_variant_stock_movement_v59() from public,anon,authenticated;
drop trigger if exists product_variant_stock_movement_v59 on public.product_variants;
drop trigger if exists product_variant_stock_insert_v59 on public.product_variants;
drop trigger if exists product_variant_stock_update_v59 on public.product_variants;
drop trigger if exists product_variant_stock_delete_v59 on public.product_variants;
create trigger product_variant_stock_insert_v59 after insert on public.product_variants
for each row execute function public.capture_variant_stock_movement_v59();
create trigger product_variant_stock_update_v59 after update of stock on public.product_variants
for each row execute function public.capture_variant_stock_movement_v59();
create trigger product_variant_stock_delete_v59 after delete on public.product_variants
for each row execute function public.capture_variant_stock_movement_v59();

create or replace function public.seller_adjust_variant_stock_v59(p_variant uuid,p_delta integer,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_variant public.product_variants%rowtype;
  v_product public.products%rowtype;
  v_new_stock bigint;
  v_reason text;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_delta is null or p_delta=0 or abs(p_delta::bigint)>100000 then raise exception 'stock_delta_invalid'; end if;
  v_reason := btrim(coalesce(p_reason,''));
  if char_length(v_reason)<3 or char_length(v_reason)>240 then raise exception 'stock_reason_invalid'; end if;
  select v.* into v_variant from public.product_variants v join public.products p on p.id=v.product_id
    join public.shops s on s.id=p.shop_id
    where v.id=p_variant and s.owner_id=auth.uid() and s.status='active'
      and coalesce(s.kind,'pro')<>'personal' for update of v;
  if not found then raise exception 'variant_not_found_or_shop_not_eligible'; end if;
  select p.* into v_product from public.products p where p.id=v_variant.product_id for update;
  v_new_stock := v_variant.stock::bigint+p_delta::bigint;
  if v_new_stock<0 then raise exception 'stock_cannot_be_negative'; end if;
  if v_new_stock>2147483647 then raise exception 'stock_limit_exceeded'; end if;
  -- Wholesale requests reserve product-level quantities, so conservatively prevent a
  -- variant adjustment that would make the aggregate product stock lower than reservations.
  if p_delta<0 then
    if v_product.stock::bigint+p_delta::bigint < (select coalesce(sum(r.quantity),0) from public.wholesale_requests r
      where r.product_id=v_product.id and r.status='accepted' and (r.expires_at is null or r.expires_at>now()))
    then raise exception 'stock_below_reserved_wholesale_quantity'; end if;
  end if;
  perform set_config('haitiket.stock_reason',v_reason,true);
  perform set_config('haitiket.stock_manual','true',true);
  update public.product_variants set stock=v_new_stock::integer where id=p_variant;
  return jsonb_build_object('variant_id',p_variant,'product_id',v_variant.product_id,'old_stock',v_variant.stock,'new_stock',v_new_stock,'delta',p_delta);
end $$;
revoke all on function public.seller_adjust_variant_stock_v59(uuid,integer,text) from public,anon;
grant execute on function public.seller_adjust_variant_stock_v59(uuid,integer,text) to authenticated;

comment on column public.product_stock_movements.variant_id is 'Variante exacte concernée; null pour les mouvements du stock agrégé du produit.';
comment on column public.product_stock_movements.reference_type is 'Type de référence métier facultatif; ne constitue pas une preuve de paiement.';
comment on column public.product_stock_movements.reference_id is 'Identifiant de référence métier facultatif.';
