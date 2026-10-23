-- HAITIKET V49: mise en avant sécurisée des produits de la boutique officielle.
-- À appliquer en staging avant production.
alter table public.products
  add column if not exists is_featured boolean not null default false;

create index if not exists products_featured_catalog_idx
  on public.products (is_featured desc, created_at desc)
  where status = 'published' and stock > 0;

create or replace function public.admin_set_official_product_featured_v49(
  p_product uuid,
  p_featured boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_shop uuid;
begin
  if auth.uid() is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : console administrateur verrouillée';
  end if;

  select p.shop_id into v_shop
  from public.products p
  join public.shops s on s.id = p.shop_id
  where p.id = p_product and s.is_official and s.kind = 'platform' and s.status = 'active'
  for update of p;

  if v_shop is null then
    raise exception 'Produit introuvable ou non rattaché à la boutique officielle active';
  end if;

  update public.products
  set is_featured = coalesce(p_featured, false),
      updated_at = now()
  where id = p_product and shop_id = v_shop;

  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason)
  values (
    auth.uid(),
    case when coalesce(p_featured, false) then 'feature_official_product' else 'unfeature_official_product' end,
    'product', p_product,
    case when coalesce(p_featured, false) then 'Produit officiel mis en avant dans le catalogue' else 'Produit officiel retiré de la sélection mise en avant' end
  );
end;
$$;

revoke all on function public.admin_set_official_product_featured_v49(uuid, boolean) from public, anon;
grant execute on function public.admin_set_official_product_featured_v49(uuid, boolean) to authenticated;
