-- HAITIKET 0056: check product-media write access without being blocked by
-- the caller's separate products SELECT RLS policy.
-- Safe additive migration; does not alter payment, wallet, product status, or orders.

begin;

create or replace function public.can_write_product_media(p_product_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.products p
    join public.shops s on s.id = p.shop_id
    where p.id = p_product_id
      and s.status = 'active'
      and (
        s.owner_id = auth.uid()
        or (coalesce(s.is_official, false) and public.admin_unlocked())
      )
  );
$$;

revoke all on function public.can_write_product_media(uuid) from public, anon;
grant execute on function public.can_write_product_media(uuid) to authenticated;

drop policy if exists media_owner_write on public.product_media;
create policy media_owner_write on public.product_media
for all
to authenticated
using (public.can_write_product_media(product_id))
with check (public.can_write_product_media(product_id));

commit;
