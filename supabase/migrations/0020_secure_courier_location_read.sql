-- HAITIKET 0020 : lecture contrôlée de la position du coursier assigné.
-- Corrige la limite d'une policy SELECT qui dépendrait de tables elles-mêmes protégées par RLS.

-- La position n'est pas lisible directement via une policy générique.
drop policy if exists courier_status_related_read on public.courier_status;

create or replace function public.get_active_courier_location(p_order uuid)
returns table (
  courier_id uuid,
  lat double precision,
  lng double precision,
  accuracy_m double precision,
  location_updated_at timestamptz
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
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;

  select * into o from public.orders where id = p_order;
  if o.id is null then
    raise exception 'Commande introuvable';
  end if;

  -- Le demandeur doit être le client de cette commande ou le propriétaire de sa boutique.
  if o.customer_id <> auth.uid() and not exists (
    select 1 from public.shops s where s.id = o.shop_id and s.owner_id = auth.uid()
  ) then
    raise exception 'Accès refusé';
  end if;

  select * into j from public.delivery_jobs where order_id = o.id;
  if j.id is null or j.courier_id is null or j.status not in ('assigned','picked_up','delivered') then
    return;
  end if;

  -- Pas de coordonnées pour une mission annulée ou une commande hors du flux actif.
  if o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED') then
    return;
  end if;

  return query
    select cs.user_id, cs.lat, cs.lng, cs.accuracy_m, cs.location_updated_at
    from public.courier_status cs
    where cs.user_id = j.courier_id
      and cs.lat is not null and cs.lng is not null
    limit 1;
end;
$$;

revoke all on function public.get_active_courier_location(uuid) from public, anon;
grant execute on function public.get_active_courier_location(uuid) to authenticated;
