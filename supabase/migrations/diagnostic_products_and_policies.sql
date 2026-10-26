-- Run this after saving the official shop settings. Share the result grids.
-- A) Effective RLS policies on product_media and products
select schemaname, tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('product_media', 'products')
order by tablename, policyname;

-- B) Most recently modified products; this shows whether a removed product
-- actually changed status or merely reappeared in the UI.
select p.id, p.name, p.status, p.updated_at, p.shop_id,
       s.name as shop_name, s.is_official, s.owner_id
from public.products p
left join public.shops s on s.id = p.shop_id
order by p.updated_at desc nulls last
limit 100;
