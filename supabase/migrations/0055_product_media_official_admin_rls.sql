-- HAITIKET hotfix 0055: autoriser l'admin déverrouillé à gérer les médias
-- des produits de la boutique officielle, sans ouvrir les médias des autres boutiques.
-- À exécuter après 0042_official_platform_shop_v48.sql.

begin;

drop policy if exists media_owner_write on public.product_media;
create policy media_owner_write on public.product_media
for all
to authenticated
using (
  exists (
    select 1
    from public.products p
    join public.shops s on s.id = p.shop_id
    where p.id = product_media.product_id
      and s.status = 'active'
      and (
        s.owner_id = auth.uid()
        or (coalesce(s.is_official, false) and public.admin_unlocked())
      )
  )
)
with check (
  exists (
    select 1
    from public.products p
    join public.shops s on s.id = p.shop_id
    where p.id = product_media.product_id
      and s.status = 'active'
      and (
        s.owner_id = auth.uid()
        or (coalesce(s.is_official, false) and public.admin_unlocked())
      )
  )
);

commit;
