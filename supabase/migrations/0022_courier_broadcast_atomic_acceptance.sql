-- HAITIKET V9.2 — diffusion géographique des missions et acceptation concurrente sûre.
-- Migration additive : ne supprime aucune donnée et ne crée aucun paiement/solde.

-- Index utiles pour filtrer rapidement les missions encore ouvertes et les GPS récents.
create index if not exists delivery_jobs_open_created_idx
  on public.delivery_jobs (created_at desc) where status = 'open';
create index if not exists courier_status_fresh_available_idx
  on public.courier_status (user_id, location_updated_at desc)
  where available = true and lat is not null and lng is not null;

-- Diffusion aux coursiers approuvés, disponibles, ayant un GPS récent et situés à <= 25 km
-- de la boutique. Le rayon est un filtre de distance à vol d'oiseau, pas un temps de trajet.
-- La signature reste compatible avec l'écran existant.
create or replace function public.list_open_jobs()
returns table (id uuid, pickup_area text, pay_minor bigint, currency text, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_lat double precision;
  v_lng double precision;
  v_updated timestamptz;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not public._is_approved_courier() then raise exception 'Candidature non approuvée'; end if;

  select cs.lat, cs.lng, cs.location_updated_at
    into v_lat, v_lng, v_updated
  from public.courier_status cs
  where cs.user_id = v_uid and cs.available = true;

  if v_lat is null or v_lng is null or v_updated is null
     or v_updated < now() - interval '3 minutes' then
    return;
  end if;

  return query
  select j.id, j.pickup_area, j.pay_minor, j.currency, j.created_at
  from public.delivery_jobs j
  join public.orders o on o.id = j.order_id
  join public.shops s on s.id = o.shop_id
  where j.status = 'open'
    and o.delivery_mode = 'delivery'
    and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP')
    and s.status = 'active'
    and s.lat is not null and s.lng is not null
    and 6371.0 * 2 * asin(sqrt(
      least(1.0, greatest(0.0,
        power(sin(radians(s.lat - v_lat) / 2), 2)
        + cos(radians(v_lat)) * cos(radians(s.lat))
        * power(sin(radians(s.lng - v_lng) / 2), 2)
      ))
    )) <= 25.0
  order by j.created_at desc
  limit 50;
end;
$$;
revoke all on function public.list_open_jobs() from public, anon;
grant execute on function public.list_open_jobs() to authenticated;

-- L'acceptation sérialise les demandes d'un même coursier avant de compter ses missions.
-- Le verrou de la ligne de mission et l'UPDATE conditionnel empêchent qu'un même job
-- soit affecté à deux coursiers en cas de clics simultanés.
create or replace function public.accept_job(p_job uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_lat double precision;
  v_lng double precision;
  v_updated timestamptz;
  v_job public.delivery_jobs;
  v_shop_lat double precision;
  v_shop_lng double precision;
  v_active_count integer;
  v_distance_km double precision;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not public._is_approved_courier() then raise exception 'Candidature non approuvée'; end if;

  -- Clé advisory par coursier : sérialise aussi les acceptations de missions différentes.
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));

  select cs.lat, cs.lng, cs.location_updated_at
    into v_lat, v_lng, v_updated
  from public.courier_status cs
  where cs.user_id = v_uid and cs.available = true
  for update;

  if v_lat is null or v_lng is null or v_updated is null
     or v_updated < now() - interval '3 minutes' then
    raise exception 'Position GPS absente ou trop ancienne : actualisez votre position';
  end if;

  select * into v_job
  from public.delivery_jobs
  where id = p_job
  for update;

  if v_job.id is null or v_job.status <> 'open' then
    raise exception 'Mission déjà prise ou indisponible';
  end if;

  select s.lat, s.lng into v_shop_lat, v_shop_lng
  from public.orders o join public.shops s on s.id = o.shop_id
  where o.id = v_job.order_id
    and o.delivery_mode = 'delivery'
    and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP')
    and s.status = 'active';

  if v_shop_lat is null or v_shop_lng is null then
    raise exception 'Position de la boutique non disponible : mission non attribuable';
  end if;

  v_distance_km := 6371.0 * 2 * asin(sqrt(least(1.0, greatest(0.0,
    power(sin(radians(v_shop_lat - v_lat) / 2), 2)
    + cos(radians(v_lat)) * cos(radians(v_shop_lat))
    * power(sin(radians(v_shop_lng - v_lng) / 2), 2)
  ))));
  if v_distance_km > 25.0 then
    raise exception 'Cette mission est hors de votre rayon de 25 km';
  end if;

  select count(*) into v_active_count
  from public.delivery_jobs
  where courier_id = v_uid and status in ('assigned','picked_up');
  if v_active_count >= 3 then
    raise exception 'Maximum de 3 missions actives simultanément';
  end if;

  update public.delivery_jobs
  set status = 'assigned', courier_id = v_uid, assigned_at = now()
  where id = p_job and status = 'open';

  if not found then raise exception 'Mission déjà prise ou indisponible'; end if;
end;
$$;
revoke all on function public.accept_job(uuid) from public, anon;
grant execute on function public.accept_job(uuid) to authenticated;

-- Autoriser la lecture des missions seulement par RPC, jamais par SELECT direct.
revoke all on public.delivery_jobs from anon, authenticated;
grant select on public.delivery_jobs to authenticated;
drop policy if exists jobs_own_read on public.delivery_jobs;
create policy jobs_assigned_read on public.delivery_jobs
  for select to authenticated using (courier_id = auth.uid());
