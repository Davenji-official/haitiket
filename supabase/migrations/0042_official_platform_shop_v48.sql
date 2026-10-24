-- HAITIKET V48 : boutique officielle de la plateforme, badge visible et exemption d'abonnement.
-- À appliquer en staging puis en production après revue.

alter table public.shops add column if not exists is_official boolean not null default false;
alter table public.shops add column if not exists official_badge_label text not null default 'Boutique officielle HAITIKET';
alter table public.shops drop constraint if exists shops_kind_check;
alter table public.shops add constraint shops_kind_check check (kind in ('pro','personal','platform'));
create unique index if not exists shops_single_official_idx on public.shops (is_official) where is_official;

create or replace function public.shop_plan_ok(p_shop uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select value from public.platform_settings where key = 'enforce_shop_plan'), 'false') <> 'true'
      or exists (select 1 from public.shops where id = p_shop and (kind = 'personal' or is_official or plan_paid_until > now()))
$$;
grant execute on function public.shop_plan_ok(uuid) to anon, authenticated;

-- Crée ou met à jour l'unique boutique officielle. Seul un admin déverrouillé peut l'utiliser.
create or replace function public.admin_save_official_shop(p_name text, p_city text, p_slogan text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.shops;
begin
  if auth.uid() is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : console administrateur verrouillée';
  end if;
  if char_length(trim(coalesce(p_name,''))) < 2 or char_length(trim(p_name)) > 80 then
    raise exception 'Le nom doit contenir entre 2 et 80 caractères';
  end if;
  if char_length(coalesce(p_slogan,'')) > 80 then raise exception 'Slogan limité à 80 caractères'; end if;

  select * into s from public.shops where is_official for update;
  if s.id is null then
    insert into public.shops(owner_id,name,city,status,kind,is_official,official_badge_label,slogan)
    values (auth.uid(),trim(p_name),nullif(trim(coalesce(p_city,'')),''),'active','platform',true,'Boutique officielle HAITIKET',nullif(trim(coalesce(p_slogan,'')),''))
    returning * into s;
    insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
    values(auth.uid(),'create_official_shop','shop',s.id,'Boutique officielle HAITIKET créée');
  else
    update public.shops set name=trim(p_name), city=nullif(trim(coalesce(p_city,'')),''),
      slogan=nullif(trim(coalesce(p_slogan,'')),''), status='active', kind='platform', is_official=true,
      official_badge_label='Boutique officielle HAITIKET'
    where id=s.id returning * into s;
    insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
    values(auth.uid(),'update_official_shop','shop',s.id,'Paramètres de la boutique officielle mis à jour');
  end if;
  return to_jsonb(s);
end $$;
revoke all on function public.admin_save_official_shop(text,text,text) from public, anon;
grant execute on function public.admin_save_official_shop(text,text,text) to authenticated;

create or replace function public.admin_get_official_shop()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.shops;
begin
  if auth.uid() is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : console administrateur verrouillée';
  end if;
  select * into s from public.shops where is_official limit 1;
  if s.id is null then return null; end if;
  return to_jsonb(s);
end $$;
revoke all on function public.admin_get_official_shop() from public, anon;
grant execute on function public.admin_get_official_shop() to authenticated;

-- Permet au propriétaire admin de personnaliser la boutique officielle avec l'éditeur existant.
create or replace function public.update_shop_branding(p_shop uuid, p_logo text, p_banner text, p_slogan text, p_primary text, p_accent text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_primary is not null and p_primary !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Couleur principale invalide'; end if;
  if p_accent is not null and p_accent !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Couleur secondaire invalide'; end if;
  if char_length(coalesce(p_slogan, '')) > 80 then raise exception 'Slogan trop long (80 caractères)'; end if;
  if coalesce(p_logo, 'https://x') !~ '^https://' or coalesce(p_banner, 'https://x') !~ '^https://' then raise exception 'Lien d''image invalide'; end if;
  update public.shops set logo_url = p_logo, banner_url = p_banner, slogan = nullif(trim(p_slogan), ''), color_primary = p_primary, color_accent = p_accent
  where id = p_shop and kind in ('pro','platform')
    and (owner_id = auth.uid() or (is_official and public.admin_unlocked()))
    and (kind <> 'platform' or (is_official and public.admin_unlocked()));
  if not found then raise exception 'Boutique professionnelle introuvable ou accès refusé'; end if;
end $$;
grant execute on function public.update_shop_branding(uuid, text, text, text, text, text) to authenticated;

-- Complète la requête publique de produits : les produits officiels restent source=marketplace.
create index if not exists shops_official_active_idx on public.shops (status, is_official) where is_official;


-- Tout admin déverrouillé peut gérer les produits de l'unique boutique officielle;
-- les autres boutiques restent limitées à leur propriétaire.
drop policy if exists products_write on public.products;
create policy products_write on public.products for all
  using (
    exists (select 1 from public.shops s where s.id = shop_id and s.status = 'active' and (
      s.owner_id = auth.uid() or (s.is_official and public.admin_unlocked())
    ))
  )
  with check (
    exists (select 1 from public.shops s where s.id = shop_id and s.status = 'active' and (
      s.owner_id = auth.uid() or (s.is_official and public.admin_unlocked())
    ))
  );

-- Lecture et gestion des commandes de la boutique officielle par tout admin déverrouillé.
drop policy if exists orders_official_admin_read on public.orders;
create policy orders_official_admin_read on public.orders for select using (
  exists (select 1 from public.shops s where s.id = shop_id and s.is_official and public.admin_unlocked())
);
drop policy if exists order_items_official_admin_read on public.order_items;
create policy order_items_official_admin_read on public.order_items for select using (
  exists (select 1 from public.orders o join public.shops s on s.id = o.shop_id
          where o.id = order_id and s.is_official and public.admin_unlocked())
);
drop policy if exists order_events_official_admin_read on public.order_status_events;
create policy order_events_official_admin_read on public.order_status_events for select using (
  exists (select 1 from public.orders o join public.shops s on s.id = o.shop_id
          where o.id = order_id and s.is_official and public.admin_unlocked())
);
drop policy if exists inventory_official_admin_read on public.inventory_movements;
create policy inventory_official_admin_read on public.inventory_movements for select using (
  exists (select 1 from public.products p join public.shops s on s.id = p.shop_id
          where p.id = product_id and s.is_official and public.admin_unlocked())
);

create or replace function public.seller_set_order_status(p_order uuid, p_to text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  select o2.* into o from public.orders o2 join public.shops s on s.id = o2.shop_id
  where o2.id = p_order and (s.owner_id = auth.uid() or (s.is_official and public.admin_unlocked()));
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if not ((o.status = 'PAID' and p_to = 'CONFIRMED') or (o.status = 'CONFIRMED' and p_to = 'PREPARING') or (o.status = 'PREPARING' and p_to = 'READY_FOR_PICKUP')) then
    raise exception 'Changement de statut non autorisé';
  end if;
  perform public._set_order_status(p_order, p_to, auth.uid(), 'seller_update');
  if p_to = 'CONFIRMED' and o.delivery_mode = 'delivery' then perform public.create_delivery_job(p_order); end if;
end $$;
grant execute on function public.seller_set_order_status(uuid, text) to authenticated;
