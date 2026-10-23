-- V53: multi-audience products, unique shop names, owner controls, courier withdrawal.
-- Resolve duplicate existing shop names before applying this migration; it fails safely if any exist.
alter table public.products add column if not exists audiences text[] not null default '{}';
update public.products set audiences = array[audience] where cardinality(audiences) = 0 and audience is not null;
create index if not exists products_audiences_gin_v53 on public.products using gin (audiences);

-- Normalize whitespace and case for uniqueness; a duplicate preflight avoids silent data changes.
do $$
begin
  if exists (
    select 1 from public.shops
    group by lower(regexp_replace(btrim(name), '\s+', ' ', 'g'))
    having count(*) > 1
  ) then
    raise exception 'V53 migration blocked: duplicate shop names exist. Rename duplicates before retrying.';
  end if;
end $$;
create unique index if not exists shops_name_normalized_unique_v53
  on public.shops (lower(regexp_replace(btrim(name), '\s+', ' ', 'g')));

create or replace function public.seller_manage_own_shop_v53(p_shop uuid, p_name text, p_action text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_shop public.shops%rowtype; v_name text;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into v_shop from public.shops where id = p_shop and owner_id = auth.uid() for update;
  if not found then raise exception 'shop_not_found_or_not_owned'; end if;
  if v_shop.kind = 'platform' or coalesce(v_shop.is_official,false) then raise exception 'official_shop_managed_by_admin'; end if;
  if p_action = 'rename' then
    v_name := regexp_replace(btrim(coalesce(p_name,'')), '\s+', ' ', 'g');
    if char_length(v_name) < 2 or char_length(v_name) > 80 then raise exception 'shop_name_length_invalid'; end if;
    if exists (select 1 from public.shops s where s.id <> p_shop and lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')) = lower(v_name)) then raise exception 'shop_name_taken'; end if;
    update public.shops set name = v_name where id = p_shop returning * into v_shop;
  elsif p_action = 'suspend' then
    if v_shop.status = 'closed' then raise exception 'shop_permanently_closed'; end if;
    update public.shops set status = 'suspended' where id = p_shop returning * into v_shop;
  elsif p_action = 'close' then
    update public.shops set status = 'closed' where id = p_shop returning * into v_shop;
  else raise exception 'invalid_shop_action';
  end if;
  return jsonb_build_object('id',v_shop.id,'name',v_shop.name,'status',v_shop.status);
end $$;
revoke all on function public.seller_manage_own_shop_v53(uuid,text,text) from public, anon;
grant execute on function public.seller_manage_own_shop_v53(uuid,text,text) to authenticated;

-- Let a courier voluntarily withdraw while preserving their application/history.
alter table public.courier_applications drop constraint if exists courier_applications_status_check;
alter table public.courier_applications add constraint courier_applications_status_check
  check (status in ('submitted','verifying','approved','rejected','suspended','withdrawn'));
create or replace function public.courier_withdraw_self_v53()
returns boolean language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  update public.courier_applications set status='withdrawn'
   where id = (select id from public.courier_applications where user_id=auth.uid() and status <> 'withdrawn' order by created_at desc limit 1)
   returning id into v_id;
  if v_id is null then raise exception 'no_active_courier_application'; end if;
  return true;
end $$;
revoke all on function public.courier_withdraw_self_v53() from public, anon;
grant execute on function public.courier_withdraw_self_v53() to authenticated;
