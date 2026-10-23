-- V60: stock traceability, shop lifecycle, KYC, verification badges and admin account controls.
-- Refund execution remains a separate provider/admin operation; this migration only queues auditable requests.

-- Preserve V58's stock-capture behavior while copying explicit business references for product-only inflows.
create or replace function public.capture_product_stock_movement_v58()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_reason text; v_type text; v_old integer; v_delta integer; v_ref_type text; v_ref_id uuid;
begin
 if tg_op='INSERT' then
   v_old:=null; v_delta:=coalesce(new.stock,0);
   if v_delta<=0 then return new; end if;
   v_type:='initial_stock'; v_reason:='Stock initial enregistré';
 else
   if new.stock is not distinct from old.stock then return new; end if;
   v_old:=old.stock; v_delta:=new.stock-old.stock; v_type:='stock_change';
   v_reason:=nullif(left(coalesce(current_setting('haitiket.stock_reason',true),''),240),'');
   if v_reason is null then v_reason:='Mise à jour du stock'; end if;
   if current_setting('haitiket.stock_manual',true)='true' then v_type:='manual_adjustment'; end if;
 end if;
 v_ref_type:=nullif(current_setting('haitiket.stock_reference_type',true),'');
 v_ref_id:=nullif(current_setting('haitiket.stock_reference_id',true),'')::uuid;
 insert into public.product_stock_movements(product_id,shop_id,movement_type,old_stock,new_stock,quantity_delta,reason,actor_id,reference_type,reference_id)
 values(new.id,new.shop_id,v_type,v_old,new.stock,v_delta,v_reason,auth.uid(),v_ref_type,v_ref_id);
 return new;
end $$;
revoke all on function public.capture_product_stock_movement_v58() from public,anon,authenticated;

-- 1) Link existing order stock movements to order IDs. The existing inventory_movements
-- rows are inserted by checkout/cancellation routines in the same transaction.
create or replace function public.link_stock_ledger_order_v60()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_variant uuid;
begin
  if new.order_id is null then return new; end if;
  select oi.variant_id into v_variant
    from public.order_items oi
   where oi.order_id=new.order_id and oi.product_id=new.product_id
     and abs(new.delta)=oi.qty and oi.variant_id is not null
   group by oi.product_id,oi.variant_id having count(*)=1
   limit 1;
  update public.product_stock_movements m
     set reference_type='order', reference_id=new.order_id
   where m.id=(select x.id from public.product_stock_movements x
      where x.product_id=new.product_id and x.quantity_delta=new.delta
        and x.reference_id is null and x.created_at >= transaction_timestamp()
      order by x.created_at desc, x.id desc limit 1);
  if v_variant is not null then
    update public.product_stock_movements m set reference_type='order', reference_id=new.order_id
      where m.id=(select x.id from public.product_stock_movements x
        where x.variant_id=v_variant and x.quantity_delta=new.delta
          and x.reference_id is null and x.created_at >= transaction_timestamp()
        order by x.created_at desc,x.id desc limit 1);
  end if;
  return new;
end $$;
revoke all on function public.link_stock_ledger_order_v60() from public,anon,authenticated;
drop trigger if exists link_stock_ledger_order_v60 on public.inventory_movements;
create trigger link_stock_ledger_order_v60 after insert on public.inventory_movements
for each row execute function public.link_stock_ledger_order_v60();

-- Wholesale fulfillment is a supplier handover (stock out). Attach the workflow reference.
create or replace function public.link_wholesale_handover_stock_v60()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status='fulfilled' and old.status is distinct from 'fulfilled' then
    update public.product_stock_movements m set reference_type='supplier_handover', reference_id=new.id
    where m.id=(select x.id from public.product_stock_movements x
      where x.product_id=new.product_id and x.quantity_delta=-new.quantity
        and x.reference_id is null and x.created_at >= transaction_timestamp()
      order by x.created_at desc,x.id desc limit 1);
  end if;
  return new;
end $$;
revoke all on function public.link_wholesale_handover_stock_v60() from public,anon,authenticated;
drop trigger if exists link_wholesale_handover_stock_v60 on public.wholesale_requests;
create trigger link_wholesale_handover_stock_v60 after update of status on public.wholesale_requests
for each row execute function public.link_wholesale_handover_stock_v60();

-- Explicit supplier receipts / returns use a locked, owner-checked RPC; no wallet/payment mutation.
create or replace function public.seller_record_stock_inflow_v60(
  p_product uuid,p_variant uuid,p_quantity integer,p_reason text,p_reference_type text default 'supplier_receipt',p_reference_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_product public.products%rowtype; v_variant public.product_variants%rowtype; v_reason text;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_quantity is null or p_quantity<1 or p_quantity>100000 then raise exception 'stock_quantity_invalid'; end if;
  v_reason:=btrim(coalesce(p_reason,''));
  if char_length(v_reason)<3 or char_length(v_reason)>240 then raise exception 'stock_reason_invalid'; end if;
  if p_reference_type is null or p_reference_type not in ('supplier_receipt','return') then raise exception 'stock_reference_type_invalid'; end if;
 if p_reference_id is not null and exists(select 1 from public.product_stock_movements m where m.reference_type=p_reference_type and m.reference_id=p_reference_id and m.product_id=p_product and m.variant_id is not distinct from p_variant) then raise exception 'stock_reference_already_recorded'; end if;
  select p.* into v_product from public.products p join public.shops s on s.id=p.shop_id
    where p.id=p_product and s.owner_id=auth.uid() and s.status='active' and coalesce(s.kind,'pro')<>'personal'
    for update of p;
  if not found then raise exception 'product_not_found_or_shop_not_eligible'; end if;
  if p_reference_id is not null and p_reference_type='return' then
    if not exists(select 1 from public.orders o join public.order_items oi on oi.order_id=o.id
      where o.id=p_reference_id and o.shop_id=v_product.shop_id and oi.product_id=p_product
        and ((p_variant is null and oi.variant_id is null) or oi.variant_id=p_variant)
        and (o.status in ('DELIVERED','COMPLETED','REFUNDED') or (o.status='CANCELLED' and exists(
          select 1 from public.order_status_events ose where ose.order_id=o.id and ose.from_status='IN_TRANSIT'
            and ose.to_status='CANCELLED' and ose.reason in ('seller_shop_suspended','seller_shop_closure_requested','shop_deletion_request'))))) then
      raise exception 'return_reference_not_eligible';
    end if;
  elsif p_reference_id is not null and p_reference_type='supplier_receipt' then
    if not exists(select 1 from public.wholesale_requests wr join public.shops bs on bs.id=wr.buyer_shop_id
      where wr.id=p_reference_id and wr.status='fulfilled' and bs.owner_id=auth.uid() and bs.id=v_product.shop_id) then
      raise exception 'supplier_receipt_reference_not_eligible';
    end if;
  end if;
  perform set_config('haitiket.stock_reason',v_reason,true);
  perform set_config('haitiket.stock_manual','true',true);
  perform set_config('haitiket.stock_reference_type',p_reference_type,true);
  perform set_config('haitiket.stock_reference_id',coalesce(p_reference_id::text,''),true);
  if p_variant is not null then
    select * into v_variant from public.product_variants where id=p_variant and product_id=p_product for update;
    if not found then raise exception 'variant_not_found_for_product'; end if;
    if v_variant.stock::bigint+p_quantity::bigint>2147483647 then raise exception 'stock_limit_exceeded'; end if;
    update public.product_variants set stock=stock+p_quantity where id=p_variant;
    return jsonb_build_object('product_id',p_product,'variant_id',p_variant,'new_stock',v_variant.stock+p_quantity,'reference_type',p_reference_type);
  else
    if exists(select 1 from public.product_variants where product_id=p_product) then
      raise exception 'variant_required_for_variant_product';
    end if;
    if v_product.stock::bigint+p_quantity::bigint>2147483647 then raise exception 'stock_limit_exceeded'; end if;
    update public.products set stock=stock+p_quantity where id=p_product;
    return jsonb_build_object('product_id',p_product,'new_stock',v_product.stock+p_quantity,'reference_type',p_reference_type);
  end if;
end $$;
revoke all on function public.seller_record_stock_inflow_v60(uuid,uuid,integer,text,text,uuid) from public,anon;
grant execute on function public.seller_record_stock_inflow_v60(uuid,uuid,integer,text,text,uuid) to authenticated;

-- Immediate order freeze/cancellation helper used on suspension and deletion request.
-- Disputed orders are deliberately held for administrator review rather than auto-refunded.
create or replace function public._freeze_shop_orders_v60(p_shop uuid,p_actor uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o record; v_cancelled integer:=0; v_refunds integer:=0; v_disputes integer:=0;
begin
 for o in select * from public.orders where shop_id=p_shop
   and status not in ('CANCELLED','REFUNDED','COMPLETED','DELIVERED') order by id for update loop
   if o.status='DISPUTED' then v_disputes:=v_disputes+1;
   elsif o.status='PENDING_PAYMENT' then
     perform public._cancel_order(o.id,p_actor,p_reason); v_cancelled:=v_cancelled+1;
   elsif o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT') then
     -- In-transit goods are not re-added to available stock until physical return is confirmed.
     if o.status<>'IN_TRANSIT' then perform public._restore_stock(o.id,p_reason,p_actor); end if;
     update public.delivery_jobs set status='cancelled' where order_id=o.id and status in ('open','assigned','picked_up');
     insert into public.refund_requests(order_id,user_id,amount_minor,reason)
       values(o.id,o.customer_id,o.total_minor,'Boutique suspendue: remboursement à exécuter') on conflict(order_id) do nothing;
     perform public._set_order_status(o.id,'CANCELLED',p_actor,p_reason);
     v_cancelled:=v_cancelled+1; v_refunds:=v_refunds+1;
   elsif o.status='PAYMENT_PROCESSING' then
     update public.payment_attempts set status='refund_required',updated_at=now()
       where order_id=o.id and status in ('created','pending','successful');
     perform public._set_order_status(o.id,'CANCELLED',p_actor,p_reason);
     v_cancelled:=v_cancelled+1;
   end if;
 end loop;
 return jsonb_build_object('cancelled_orders',v_cancelled,'refunds_queued',v_refunds,'disputed_orders_held',v_disputes);
end $$;
revoke all on function public._freeze_shop_orders_v60(uuid,uuid,text) from public,anon,authenticated;

create or replace function public.seller_manage_own_shop_v53(p_shop uuid,p_name text,p_action text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_shop public.shops%rowtype; v_name text; v_order_result jsonb:='{}'::jsonb;
begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 select * into v_shop from public.shops where id=p_shop and owner_id=auth.uid() for update;
 if not found then raise exception 'shop_not_found_or_not_owned'; end if;
 if v_shop.kind='platform' or coalesce(v_shop.is_official,false) then raise exception 'official_shop_managed_by_admin'; end if;
 if p_action='rename' then
   v_name:=regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g');
   if char_length(v_name)<2 or char_length(v_name)>80 then raise exception 'shop_name_length_invalid'; end if;
   if exists(select 1 from public.shops s where s.id<>p_shop and lower(regexp_replace(btrim(s.name),'\s+',' ','g'))=lower(v_name)) then raise exception 'shop_name_taken'; end if;
   update public.shops set name=v_name where id=p_shop returning * into v_shop;
 elsif p_action='suspend' then
   if v_shop.status='closed' then raise exception 'shop_permanently_closed'; end if;
   update public.shops set status='suspended' where id=p_shop returning * into v_shop;
   v_order_result:=public._freeze_shop_orders_v60(p_shop,auth.uid(),'seller_shop_suspended');
 elsif p_action='close' then
   v_order_result:=public._freeze_shop_orders_v60(p_shop,auth.uid(),'seller_shop_closure_requested');
   update public.shops set status='suspended',deletion_requested_at=coalesce(deletion_requested_at,now()),
     deletion_scheduled_at=coalesce(deletion_scheduled_at,now()+interval '30 days'),deletion_review_status='pending_admin'
     where id=p_shop returning * into v_shop;
 else raise exception 'invalid_shop_action'; end if;
 insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
   values(auth.uid(),'seller_shop_'||p_action,'shop',p_shop,'Action vendeur; gel des commandes appliqué');
 return jsonb_build_object('id',v_shop.id,'name',v_shop.name,'status',v_shop.status,'order_handling',v_order_result);
end $$;
revoke all on function public.seller_manage_own_shop_v53(uuid,text,text) from public,anon;
grant execute on function public.seller_manage_own_shop_v53(uuid,text,text) to authenticated;

-- 2) Shop deletion request: 30-day cooling-off period and explicit admin approval.
alter table public.shops add column if not exists verified_at timestamptz;
alter table public.shops add column if not exists deletion_requested_at timestamptz;
alter table public.shops add column if not exists deletion_scheduled_at timestamptz;
alter table public.shops add column if not exists deletion_review_status text not null default 'none'
  check(deletion_review_status in ('none','pending_admin','approved','rejected','completed'));
alter table public.shops add column if not exists deletion_reviewed_by uuid references auth.users(id);
alter table public.shops add column if not exists deletion_reviewed_at timestamptz;
create index if not exists shops_deletion_review_v60 on public.shops(deletion_review_status,deletion_scheduled_at)
  where deletion_review_status in ('pending_admin','approved');

create or replace function public.seller_request_shop_deletion_v60(p_shop uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.shops%rowtype; v_reason text;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  v_reason:=btrim(coalesce(p_reason,''));
  if char_length(v_reason)<5 or char_length(v_reason)>500 then raise exception 'deletion_reason_invalid'; end if;
  select * into s from public.shops where id=p_shop and owner_id=auth.uid() for update;
  if not found then raise exception 'shop_not_found_or_not_owned'; end if;
  if s.kind='platform' or coalesce(s.is_official,false) then raise exception 'official_shop_managed_by_admin'; end if;
  if s.deletion_review_status in ('pending_admin','approved','completed') then raise exception 'deletion_already_requested'; end if;
  update public.shops set status='suspended',deletion_requested_at=now(),deletion_scheduled_at=now()+interval '30 days',
    deletion_review_status='pending_admin' where id=p_shop returning * into s;
  perform public._freeze_shop_orders_v60(p_shop,auth.uid(),'shop_deletion_request');
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
    values(auth.uid(),'shop_deletion_requested','shop',p_shop,left(v_reason,200));
  return jsonb_build_object('shop_id',s.id,'status',s.status,'review_status',s.deletion_review_status,
    'deletion_scheduled_at',s.deletion_scheduled_at,'message','Boutique suspendue; examen administratif requis; délai minimal de 30 jours.');
end $$;
revoke all on function public.seller_request_shop_deletion_v60(uuid,text) from public,anon;
grant execute on function public.seller_request_shop_deletion_v60(uuid,text) to authenticated;

-- Admin review. On approval, cancel unpaid reservations and queue refunds for paid/in-progress orders.
-- A refund is NOT marked executed here: the provider must actually return funds first.
create or replace function public.admin_review_shop_deletion_v60(p_shop uuid,p_approve boolean,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.shops%rowtype; o record; v_cancelled integer:=0; v_refunds integer:=0; v_inflight integer:=0;
begin
  if not public.admin_unlocked() then raise exception 'admin_console_locked'; end if;
  select * into s from public.shops where id=p_shop for update;
  if not found or s.deletion_review_status<>'pending_admin' then raise exception 'shop_deletion_request_not_pending'; end if;
  if char_length(btrim(coalesce(p_reason,'')))<3 then raise exception 'admin_reason_required'; end if;
  if not p_approve then
    update public.shops set deletion_review_status='rejected',deletion_reviewed_by=auth.uid(),deletion_reviewed_at=now(),status='active',
      deletion_scheduled_at=null where id=p_shop;
    insert into public.admin_audit_logs(actor,action,resource,resource_id,reason) values(auth.uid(),'shop_deletion_rejected','shop',p_shop,left(p_reason,200));
    return jsonb_build_object('shop_id',p_shop,'review_status','rejected','cancelled_orders',0,'refunds_queued',0);
  end if;
  -- Keep history. Any order already in a dispute is held for human review, never auto-refunded.
  select count(*) into v_inflight from public.orders where shop_id=p_shop and status='DISPUTED';
  if v_inflight>0 then raise exception 'shop_has_disputed_orders_manual_review_required'; end if;
  for o in select * from public.orders where shop_id=p_shop and status not in ('CANCELLED','REFUNDED','COMPLETED','DELIVERED') order by id for update loop
    if o.status='PENDING_PAYMENT' then
      perform public._cancel_order(o.id,auth.uid(),'shop_deletion_request');
      v_cancelled:=v_cancelled+1;
    elsif o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','PAYMENT_PROCESSING') then
      -- If payment is captured or may have completed, enqueue idempotently; provider action remains manual.
      if o.status<>'PAYMENT_PROCESSING' then
        perform public._restore_stock(o.id,'shop_deletion_request',auth.uid());
      end if;
      update public.delivery_jobs set status='cancelled' where order_id=o.id and status in ('open','assigned','picked_up');
      if o.status<>'PAYMENT_PROCESSING' then
        insert into public.refund_requests(order_id,user_id,amount_minor,reason)
          values(o.id,o.customer_id,o.total_minor,'Fermeture de boutique: remboursement à exécuter') on conflict(order_id) do nothing;
        v_refunds:=v_refunds+1;
      else
        update public.payment_attempts set status='refund_required',updated_at=now()
          where order_id=o.id and status in ('created','pending','successful');
      end if;
      perform public._set_order_status(o.id,'CANCELLED',auth.uid(),'shop_deletion_request');
      v_cancelled:=v_cancelled+1;
    end if;
  end loop;
  update public.shops set deletion_review_status='approved',deletion_reviewed_by=auth.uid(),deletion_reviewed_at=now(),
    deletion_scheduled_at=coalesce(deletion_scheduled_at,now()+interval '30 days'),status='suspended'
    where id=p_shop;
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason) values(auth.uid(),'shop_deletion_approved','shop',p_shop,left(p_reason,200));
  return jsonb_build_object('shop_id',p_shop,'review_status','approved','cancelled_orders',v_cancelled,'refunds_queued',v_refunds,
    'deletion_scheduled_at',coalesce(s.deletion_scheduled_at,now()+interval '30 days'));
end $$;
revoke all on function public.admin_review_shop_deletion_v60(uuid,boolean,text) from public,anon;
grant execute on function public.admin_review_shop_deletion_v60(uuid,boolean,text) to authenticated;

-- Finalize only after 30 days, approval, and no unresolved refunds/disputes/in-flight orders.
create or replace function public.admin_finalize_shop_deletion_v60(p_shop uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare s public.shops%rowtype;
begin
  if not public.admin_unlocked() then raise exception 'admin_console_locked'; end if;
  select * into s from public.shops where id=p_shop for update;
  if not found or s.deletion_review_status<>'approved' then raise exception 'shop_deletion_not_approved'; end if;
  if s.deletion_scheduled_at>now() then raise exception 'shop_deletion_cooling_off_period_active'; end if;
  if exists(select 1 from public.orders where shop_id=p_shop and status not in ('CANCELLED','REFUNDED','COMPLETED','DELIVERED')) then raise exception 'shop_has_inflight_orders'; end if;
  if exists(select 1 from public.orders o join public.refund_requests r on r.order_id=o.id where o.shop_id=p_shop and r.status<>'executed') then raise exception 'shop_has_unresolved_refunds'; end if;
  update public.shops set status='closed',deletion_review_status='completed' where id=p_shop;
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason) values(auth.uid(),'shop_deletion_finalized','shop',p_shop,'Délai de 30 jours écoulé; historique conservé');
  return true;
end $$;
revoke all on function public.admin_finalize_shop_deletion_v60(uuid) from public,anon;
grant execute on function public.admin_finalize_shop_deletion_v60(uuid) to authenticated;

-- 3) KYC. Paths refer to a private storage bucket; never store document bytes in public tables.
create table if not exists public.identity_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  date_of_birth date not null,
  age_at_submission integer not null,
  identity_document_type text check(identity_document_type in ('cin_ninu','passport','drivers_license','birth_certificate','minor_guardian')),
  identity_document_path text,
  birth_certificate_path text,
  guardian_full_name text,
  guardian_date_of_birth date,
  guardian_document_path text,
  recent_photo_path text not null,
  status text not null default 'pending' check(status in ('pending','approved','rejected','needs_changes')),
  reviewer_id uuid references auth.users(id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(age_at_submission >= 0)
);
create index if not exists identity_verifications_review_v60 on public.identity_verifications(status,created_at desc);
alter table public.identity_verifications enable row level security;
drop policy if exists identity_verifications_self_read_v60 on public.identity_verifications;
create policy identity_verifications_self_read_v60 on public.identity_verifications for select to authenticated using(user_id=auth.uid());
drop policy if exists identity_verifications_admin_read_v60 on public.identity_verifications;
create policy identity_verifications_admin_read_v60 on public.identity_verifications for select to authenticated using(public.admin_unlocked());
revoke insert,update,delete on public.identity_verifications from public,anon,authenticated;

-- A courier application cannot be submitted until a KYC dossier has at least been submitted.
drop policy if exists courier_self_insert on public.courier_applications;
create policy courier_self_insert on public.courier_applications for insert to authenticated with check (
  user_id=auth.uid() and status='submitted' and exists(select 1 from public.identity_verifications iv where iv.user_id=auth.uid() and iv.status in ('pending','approved'))
);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('kyc-private','kyc-private',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists kyc_private_upload_own_v60 on storage.objects;
create policy kyc_private_upload_own_v60 on storage.objects for insert to authenticated
  with check(bucket_id='kyc-private' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists kyc_private_read_own_v60 on storage.objects;
create policy kyc_private_read_own_v60 on storage.objects for select to authenticated
  using(bucket_id='kyc-private' and ((storage.foldername(name))[1]=auth.uid()::text or public.admin_unlocked()));
drop policy if exists kyc_private_update_own_v60 on storage.objects;
create policy kyc_private_update_own_v60 on storage.objects for update to authenticated
  using(bucket_id='kyc-private' and (storage.foldername(name))[1]=auth.uid()::text)
  with check(bucket_id='kyc-private' and (storage.foldername(name))[1]=auth.uid()::text);

create or replace function public.submit_identity_verification_v60(
 p_dob date,p_document_type text,p_document_path text,p_birth_certificate_path text,
 p_guardian_name text,p_guardian_dob date,p_guardian_document_path text,p_recent_photo_path text
) returns uuid language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); v_age integer; v_id uuid;
begin
 if uid is null then raise exception 'authentication_required'; end if;
 if p_dob is null or p_dob>current_date or p_dob<date '1900-01-01' then raise exception 'date_of_birth_invalid'; end if;
 v_age:=extract(year from age(current_date,p_dob))::integer;
 if p_recent_photo_path is null or p_recent_photo_path not like uid::text||'/%'
    or not exists(select 1 from storage.objects where bucket_id='kyc-private' and name=p_recent_photo_path) then
   raise exception 'recent_photo_required'; end if;
 if v_age>=18 then
   if p_document_type not in ('cin_ninu','passport','drivers_license') or p_document_path is null or p_document_path not like uid::text||'/%'
      or not exists(select 1 from storage.objects where bucket_id='kyc-private' and name=p_document_path) then
     raise exception 'adult_identity_document_required'; end if;
 else
   if p_document_type<>'minor_guardian' or p_birth_certificate_path is null or p_birth_certificate_path not like uid::text||'/%'
      or not exists(select 1 from storage.objects where bucket_id='kyc-private' and name=p_birth_certificate_path)
      or p_guardian_document_path is null or p_guardian_document_path not like uid::text||'/%'
      or not exists(select 1 from storage.objects where bucket_id='kyc-private' and name=p_guardian_document_path)
      or char_length(btrim(coalesce(p_guardian_name,'')))<3 or p_guardian_dob is null
      or p_guardian_dob>current_date or extract(year from age(current_date,p_guardian_dob))<18 then
     raise exception 'minor_birth_certificate_and_adult_guardian_documents_required'; end if;
 end if;
 if exists(select 1 from public.identity_verifications where user_id=uid and status='approved') then raise exception 'identity_already_verified'; end if;
 if exists(select 1 from public.identity_verifications where user_id=uid and status='pending') then raise exception 'verification_already_pending'; end if;
 insert into public.identity_verifications(user_id,date_of_birth,age_at_submission,identity_document_type,identity_document_path,
   birth_certificate_path,guardian_full_name,guardian_date_of_birth,guardian_document_path,recent_photo_path)
 values(uid,p_dob,v_age,p_document_type,nullif(p_document_path,''),nullif(p_birth_certificate_path,''),nullif(btrim(p_guardian_name),''),p_guardian_dob,
   nullif(p_guardian_document_path,''),p_recent_photo_path) returning id into v_id;
 return v_id;
end $$;
revoke all on function public.submit_identity_verification_v60(date,text,text,text,text,date,text,text) from public,anon;
grant execute on function public.submit_identity_verification_v60(date,text,text,text,text,date,text,text) to authenticated;

create or replace function public.admin_review_identity_verification_v60(p_id uuid,p_status text,p_note text)
returns void language plpgsql security definer set search_path=public as $$
declare v public.identity_verifications%rowtype;
begin
 if not public.admin_unlocked() then raise exception 'admin_console_locked'; end if;
 if p_status not in ('approved','rejected','needs_changes') then raise exception 'identity_review_status_invalid'; end if;
 select * into v from public.identity_verifications where id=p_id for update;
 if not found or v.status<>'pending' then raise exception 'identity_verification_not_pending'; end if;
 update public.identity_verifications set status=p_status,reviewer_id=auth.uid(),reviewed_at=now(),review_note=left(coalesce(p_note,''),1000),updated_at=now() where id=p_id;
 if p_status='approved' then
   update public.courier_applications set status='approved',verified_at=coalesce(verified_at,now()) where user_id=v.user_id and status in ('submitted','verifying');
   update public.shops set verified_at=coalesce(verified_at,now()) where owner_id=v.user_id and status='active';
 end if;
 insert into public.admin_audit_logs(actor,action,resource,resource_id,reason) values(auth.uid(),'identity_verification_'||p_status,'identity_verification',p_id,left(coalesce(p_note,''),200));
end $$;
revoke all on function public.admin_review_identity_verification_v60(uuid,text,text) from public,anon;
grant execute on function public.admin_review_identity_verification_v60(uuid,text,text) to authenticated;

-- KYC approval is required before activating an ordinary shop or approving a courier.
create or replace function public.guard_verified_activation_v60()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_table_name='shops' and new.status='active' and old.status is distinct from 'active' and not coalesce(new.is_official,false) and coalesce(new.kind,'pro')<>'platform' then
   if not exists(select 1 from public.identity_verifications iv where iv.user_id=new.owner_id and iv.status='approved') then
     raise exception 'approved_kyc_required_before_shop_activation';
   end if;
   new.verified_at:=coalesce(new.verified_at,now());
 elsif tg_table_name='courier_applications' and new.status='approved' and old.status is distinct from 'approved' then
   if not exists(select 1 from public.identity_verifications iv where iv.user_id=new.user_id and iv.status='approved') then
     raise exception 'approved_kyc_required_before_courier_approval';
   end if;
   new.verified_at:=coalesce(new.verified_at,now());
 end if;
 return new;
end $$;
revoke all on function public.guard_verified_activation_v60() from public,anon,authenticated;
drop trigger if exists guard_shop_activation_kyc_v60 on public.shops;
create trigger guard_shop_activation_kyc_v60 before update of status on public.shops
for each row execute function public.guard_verified_activation_v60();
drop trigger if exists guard_courier_approval_kyc_v60 on public.courier_applications;
create trigger guard_courier_approval_kyc_v60 before update of status on public.courier_applications
for each row execute function public.guard_verified_activation_v60();
update public.shops s set verified_at=coalesce(s.verified_at,now()) where s.status='active'
 and exists(select 1 from public.identity_verifications iv where iv.user_id=s.owner_id and iv.status='approved');
update public.courier_applications c set verified_at=coalesce(c.verified_at,now()) where c.status='approved'
 and exists(select 1 from public.identity_verifications iv where iv.user_id=c.user_id and iv.status='approved');

-- 4) Verified courier/shop badges and account moderation. Deletion is soft to preserve order/audit history.
alter table public.courier_applications add column if not exists verified_at timestamptz;
alter table public.profiles add column if not exists account_status text not null default 'active' check(account_status in ('active','banned','deleted'));
alter table public.profiles add column if not exists account_status_reason text;
alter table public.profiles add column if not exists account_status_updated_at timestamptz;
drop policy if exists profiles_admin_read_v60 on public.profiles;
create policy profiles_admin_read_v60 on public.profiles for select to authenticated using(public.admin_unlocked());

create or replace function public.admin_manage_user_v60(p_user uuid,p_action text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_status text;
begin
 if not public.admin_unlocked() then raise exception 'admin_console_locked'; end if;
 if p_user=auth.uid() then raise exception 'cannot_moderate_own_admin_account'; end if;
 if p_action not in ('ban','unban','soft_delete') then raise exception 'user_action_invalid'; end if;
 if p_action='unban' and exists(select 1 from public.profiles where id=p_user and account_status='deleted') then raise exception 'deleted_account_cannot_be_unbanned'; end if;
 if char_length(btrim(coalesce(p_reason,'')))<3 then raise exception 'admin_reason_required'; end if;
 if p_action='ban' then v_status:='banned';
 elsif p_action='unban' then v_status:='active';
 else v_status:='deleted'; end if;
 update public.profiles set account_status=v_status,account_status_reason=left(p_reason,500),account_status_updated_at=now(),
   suspended=(v_status in ('banned','deleted')),suspended_reason=case when v_status in ('banned','deleted') then left(p_reason,200) else null end,
   display_name=case when v_status='deleted' then 'Compte supprimé' else display_name end,
   phone=case when v_status='deleted' then null else phone end
 where id=p_user;
 if not found then raise exception 'user_profile_not_found'; end if;
 -- Supabase GoTrue uses auth.users.banned_until to block login/token refresh for banned accounts.
 update auth.users set banned_until=case when v_status in ('banned','deleted') then now()+interval '100 years' else null end
   where id=p_user;
 if v_status in ('banned','deleted') then
   update public.listings set status='blocked' where seller_id=p_user and status='published';
   update public.shops set status='suspended' where owner_id=p_user and status='active' and not coalesce(is_official,false);
   update public.courier_applications set status='suspended' where user_id=p_user and status='approved';
 end if;
 insert into public.admin_audit_logs(actor,action,resource,resource_id,reason) values(auth.uid(),'user_'||p_action,'user',p_user,left(p_reason,200));
 return jsonb_build_object('user_id',p_user,'account_status',v_status,'soft_delete',v_status='deleted');
end $$;
revoke all on function public.admin_manage_user_v60(uuid,text,text) from public,anon;
grant execute on function public.admin_manage_user_v60(uuid,text,text) to authenticated;

create or replace function public.my_verification_badges_v60()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare uid uuid:=auth.uid();
begin
 if uid is null then raise exception 'authentication_required'; end if;
 return jsonb_build_object(
   'verified_shops',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'badge','Boutique vérifiée')) from public.shops where owner_id=uid and verified_at is not null and status='active'),'[]'::jsonb),
   'verified_courier',exists(select 1 from public.courier_applications where user_id=uid and status='approved' and verified_at is not null),
   'identity_status',(select status from public.identity_verifications where user_id=uid order by created_at desc limit 1)
 );
end $$;
revoke all on function public.my_verification_badges_v60() from public,anon;
grant execute on function public.my_verification_badges_v60() to authenticated;

comment on table public.identity_verifications is 'Données KYC sensibles. Documents stockés dans le bucket privé kyc-private; accès administrateur déverrouillé uniquement.';
comment on column public.shops.verified_at is 'Badge boutique vérifiée après examen KYC administratif.';
comment on column public.courier_applications.verified_at is 'Badge livreur vérifié après examen KYC administratif.';
