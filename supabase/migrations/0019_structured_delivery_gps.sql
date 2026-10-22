-- HAITIKET 0019: coordonnées structurées pour les destinations et présence GPS des coursiers.
-- Migration additive : ne supprime ni ne réécrit les commandes existantes.

alter table public.orders
  add column if not exists delivery_lat double precision,
  add column if not exists delivery_lng double precision,
  add column if not exists delivery_location_accuracy_m double precision,
  add column if not exists delivery_location_updated_at timestamptz;

alter table public.courier_status
  add column if not exists lat double precision,
  add column if not exists lng double precision,
  add column if not exists accuracy_m double precision,
  add column if not exists location_updated_at timestamptz;

alter table public.orders
  drop constraint if exists orders_delivery_lat_valid,
  add constraint orders_delivery_lat_valid check (delivery_lat is null or delivery_lat between -90 and 90),
  drop constraint if exists orders_delivery_lng_valid,
  add constraint orders_delivery_lng_valid check (delivery_lng is null or delivery_lng between -180 and 180);

alter table public.courier_status
  drop constraint if exists courier_status_lat_valid,
  add constraint courier_status_lat_valid check (lat is null or lat between -90 and 90),
  drop constraint if exists courier_status_lng_valid,
  add constraint courier_status_lng_valid check (lng is null or lng between -180 and 180);

create index if not exists courier_status_location_idx
  on public.courier_status (available, location_updated_at desc)
  where lat is not null and lng is not null;

-- Le client ne peut associer des coordonnées qu'à sa propre commande en livraison.
-- Les coordonnées sont séparées du texte de l'adresse et ne sont pas accessibles publiquement.
create or replace function public.set_order_delivery_location(
  p_order uuid,
  p_lat double precision,
  p_lng double precision,
  p_accuracy_m double precision default null
) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if p_lat is null or p_lng is null or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
    raise exception 'Coordonnées GPS invalides';
  end if;
  if p_accuracy_m is not null and (p_accuracy_m < 0 or p_accuracy_m > 100000) then
    raise exception 'Précision GPS invalide';
  end if;
  select * into o from public.orders where id = p_order for update;
  if o.id is null or o.customer_id <> auth.uid() then raise exception 'Commande introuvable ou accès refusé'; end if;
  if o.delivery_mode <> 'delivery' or o.status not in ('PENDING_PAYMENT','PAYMENT_PROCESSING','PAID','CONFIRMED') then
    raise exception 'La destination ne peut plus être modifiée pour cette commande';
  end if;
  update public.orders set delivery_lat = p_lat, delivery_lng = p_lng,
    delivery_location_accuracy_m = p_accuracy_m, delivery_location_updated_at = now()
  where id = p_order;
end $$;
revoke all on function public.set_order_delivery_location(uuid,double precision,double precision,double precision) from public, anon;
grant execute on function public.set_order_delivery_location(uuid,double precision,double precision,double precision) to authenticated;

-- La position n'est écrite que par RPC : aucune écriture directe par le client.
create or replace function public.publish_courier_location(
  p_lat double precision,
  p_lng double precision,
  p_accuracy_m double precision default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if not public._is_approved_courier() then raise exception 'Coursier non approuvé'; end if;
  if p_lat is null or p_lng is null or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
    raise exception 'Coordonnées GPS invalides';
  end if;
  if p_accuracy_m is not null and (p_accuracy_m < 0 or p_accuracy_m > 100000) then
    raise exception 'Précision GPS invalide';
  end if;
  insert into public.courier_status(user_id, available, lat, lng, accuracy_m, location_updated_at, updated_at)
  values (auth.uid(), false, p_lat, p_lng, p_accuracy_m, now(), now())
  on conflict (user_id) do update set lat = excluded.lat, lng = excluded.lng,
    accuracy_m = excluded.accuracy_m, location_updated_at = now(), updated_at = now();
end $$;
revoke all on function public.publish_courier_location(double precision,double precision,double precision) from public, anon;
grant execute on function public.publish_courier_location(double precision,double precision,double precision) to authenticated;

-- Le client et le propriétaire de la boutique ne peuvent lire la position que du coursier
-- affecté à une commande active. Le coursier peut toujours lire sa propre position.
drop policy if exists courier_status_related_read on public.courier_status;
create policy courier_status_related_read on public.courier_status for select using (
  user_id = auth.uid()
  or exists (
    select 1 from public.delivery_jobs j
    join public.orders o on o.id = j.order_id
    join public.shops s on s.id = o.shop_id
    where j.courier_id = courier_status.user_id
      and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED')
      and (o.customer_id = auth.uid() or s.owner_id = auth.uid())
  )
);

-- Realtime est activé de manière idempotente. Si la publication n'est pas accessible,
-- la migration continue et indique qu'il faut activer la table depuis Supabase Dashboard.
do $$ begin
  alter publication supabase_realtime add table public.courier_status;
exception when duplicate_object then null;
when undefined_object then raise notice 'Publication supabase_realtime absente : activer courier_status dans Database > Replication';
when insufficient_privilege then raise notice 'Droits insuffisants pour modifier supabase_realtime : activer courier_status dans Database > Replication';
end $$;
