-- HAITIKET V9.1 : expose uniquement au client/propriétaire les coordonnées réelles
-- de destination et l'horodatage réel de la dernière position du coursier.
-- À appliquer dans Supabase avant d'utiliser la nouvelle version de l'écran.
-- IMPORTANT: PostgreSQL ne permet pas de changer le type de retour OUT avec CREATE OR REPLACE.
-- DROP puis recréation est nécessaire si la fonction de 0020 existe avec l’ancien contrat.
drop function if exists public.get_active_courier_location(uuid);

create function public.get_active_courier_location(p_order uuid)
returns table (
  courier_id uuid,
  lat double precision,
  lng double precision,
  accuracy_m double precision,
  location_updated_at timestamptz,
  destination_lat double precision,
  destination_lng double precision,
  destination_location_updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  o public.orders;
  j public.delivery_jobs;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into o from public.orders where id = p_order;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if o.customer_id <> auth.uid() and not exists (
    select 1 from public.shops s where s.id = o.shop_id and s.owner_id = auth.uid()
  ) then raise exception 'Accès refusé'; end if;
  select * into j from public.delivery_jobs where order_id = o.id;
  if j.id is null or j.courier_id is null or j.status not in ('assigned','picked_up','delivered') then return; end if;
  if o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED') then return; end if;
  return query
    select j.courier_id, cs.lat, cs.lng, cs.accuracy_m, cs.location_updated_at,
           o.delivery_lat, o.delivery_lng, o.delivery_location_updated_at
    from (select 1) seed
    left join public.courier_status cs on cs.user_id = j.courier_id;

end;
$$;
revoke all on function public.get_active_courier_location(uuid) from public, anon;
grant execute on function public.get_active_courier_location(uuid) to authenticated;
