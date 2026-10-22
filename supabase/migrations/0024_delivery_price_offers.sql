-- HAITIKET V14 / V9.4 : offres de prix des coursiers choisies par le client.
-- Cette migration ajoute le socle serveur ; l'interface client/coursier doit être raccordée ensuite.
-- Aucune opération financière n'est créée ici et aucune rémunération n'est versée.

create table if not exists public.delivery_job_offers (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.delivery_jobs(id) on delete cascade,
  courier_id uuid not null references auth.users(id) on delete restrict,
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null check (currency in ('HTG','USD')),
  eta_minutes integer not null check (eta_minutes between 1 and 1440),
  note text,
  status text not null default 'pending' check (status in ('pending','selected','rejected','expired','withdrawn')),
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(job_id, courier_id)
);
create index if not exists delivery_job_offers_customer_view_idx
  on public.delivery_job_offers(job_id, status, amount_minor, created_at);
create index if not exists delivery_job_offers_courier_view_idx
  on public.delivery_job_offers(courier_id, status, created_at desc);

alter table public.delivery_job_offers enable row level security;
revoke all on public.delivery_job_offers from anon, authenticated;
-- Les accès passent exclusivement par des RPC qui vérifient le client/coursier autorisé.

create or replace function public.propose_delivery_price(
  p_job uuid, p_amount_minor bigint, p_currency text, p_eta_minutes integer, p_note text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_job public.delivery_jobs; v_lat double precision; v_lng double precision;
  v_updated timestamptz; v_shop_lat double precision; v_shop_lng double precision;
  v_distance double precision; v_id uuid;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not public._is_approved_courier() then raise exception 'Coursier non approuvé'; end if;
  if p_amount_minor is null or p_amount_minor <= 0 then raise exception 'Prix de livraison invalide'; end if;
  if p_currency not in ('HTG','USD') then raise exception 'Devise invalide'; end if;
  if p_eta_minutes is null or p_eta_minutes < 1 or p_eta_minutes > 1440 then raise exception 'Délai estimé invalide'; end if;
  if length(coalesce(p_note,'')) > 500 then raise exception 'Note trop longue'; end if;

  select * into v_job from public.delivery_jobs where id=p_job for update;
  if v_job.id is null or v_job.status <> 'open' then raise exception 'Mission non disponible'; end if;
  if v_job.currency <> p_currency then raise exception 'La devise doit correspondre à celle de la mission'; end if;

  select lat,lng,location_updated_at into v_lat,v_lng,v_updated
  from public.courier_status where user_id=v_uid and available=true;
  if v_lat is null or v_lng is null or v_updated is null or v_updated < now()-interval '3 minutes' then
    raise exception 'Position GPS absente ou trop ancienne';
  end if;
  select s.lat,s.lng into v_shop_lat,v_shop_lng
  from public.orders o join public.shops s on s.id=o.shop_id
  where o.id=v_job.order_id and o.delivery_mode='delivery'
    and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') and s.status='active';
  if v_shop_lat is null or v_shop_lng is null then raise exception 'Position de collecte indisponible'; end if;
  v_distance := 6371.0 * 2 * asin(sqrt(least(1.0,greatest(0.0,
    power(sin(radians(v_shop_lat-v_lat)/2),2) + cos(radians(v_lat))*cos(radians(v_shop_lat))*power(sin(radians(v_shop_lng-v_lng)/2),2)
  ))));
  if v_distance > 25.0 then raise exception 'Mission hors du rayon autorisé de 25 km'; end if;

  insert into public.delivery_job_offers(job_id,courier_id,amount_minor,currency,eta_minutes,note,status,expires_at,updated_at)
  values(p_job,v_uid,p_amount_minor,p_currency,p_eta_minutes,nullif(trim(coalesce(p_note,'')),''),'pending',now()+interval '10 minutes',now())
  on conflict(job_id,courier_id) do update set
    amount_minor=excluded.amount_minor, currency=excluded.currency, eta_minutes=excluded.eta_minutes,
    note=excluded.note, status='pending', expires_at=excluded.expires_at, updated_at=now()
  where public.delivery_job_offers.status in ('pending','expired','withdrawn')
  returning id into v_id;
  if v_id is null then raise exception 'Une offre a déjà été sélectionnée ou cette offre ne peut plus être modifiée'; end if;
  return v_id;
end $$;

create or replace function public.list_delivery_price_offers(p_job uuid)
returns table(offer_id uuid, courier_id uuid, courier_name text, amount_minor bigint, currency text, eta_minutes integer, note text, expires_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not exists(select 1 from public.delivery_jobs j join public.orders o on o.id=j.order_id where j.id=p_job and o.customer_id=v_uid and o.delivery_mode='delivery') then
    raise exception 'Mission introuvable ou accès refusé';
  end if;
  update public.delivery_job_offers set status='expired',updated_at=now()
    where job_id=p_job and status='pending' and expires_at<=now();
  return query
  select f.id,f.courier_id,coalesce(p.display_name,'Coursier HAITIKET'),f.amount_minor,f.currency,f.eta_minutes,f.note,f.expires_at,f.created_at
  from public.delivery_job_offers f left join public.profiles p on p.id=f.courier_id
  where f.job_id=p_job and f.status='pending' and f.expires_at>now()
  order by f.amount_minor asc, f.eta_minutes asc, f.created_at asc;
end $$;

create or replace function public.select_delivery_price_offer(p_offer uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_offer public.delivery_job_offers; v_job public.delivery_jobs;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  select f.* into v_offer from public.delivery_job_offers f where f.id=p_offer for update;
  if v_offer.id is null then raise exception 'Offre introuvable'; end if;
  select j.* into v_job from public.delivery_jobs j where j.id=v_offer.job_id for update;
  if v_job.id is null or v_job.status<>'open' then raise exception 'La mission a déjà été attribuée ou fermée'; end if;
  if not exists(select 1 from public.orders o where o.id=v_job.order_id and o.customer_id=v_uid and o.delivery_mode='delivery') then
    raise exception 'Seul le client de la commande peut choisir le prix';
  end if;
  if v_offer.status<>'pending' or v_offer.expires_at<=now() then raise exception 'Cette offre a expiré'; end if;
  if not exists(select 1 from public.courier_status cs where cs.user_id=v_offer.courier_id and cs.available=true and cs.location_updated_at>now()-interval '3 minutes') then
    raise exception 'Le coursier n’est plus disponible ou sa position est trop ancienne';
  end if;
  update public.delivery_jobs set status='assigned',courier_id=v_offer.courier_id,assigned_at=now(),pay_minor=v_offer.amount_minor,currency=v_offer.currency
    where id=v_job.id and status='open';
  if not found then raise exception 'La mission a été attribuée simultanément à un autre coursier'; end if;
  update public.delivery_job_offers set status='selected',updated_at=now() where id=p_offer;
  update public.delivery_job_offers set status='rejected',updated_at=now()
    where job_id=v_job.id and id<>p_offer and status='pending';
end $$;

revoke all on function public.propose_delivery_price(uuid,bigint,text,integer,text) from public,anon;
revoke all on function public.list_delivery_price_offers(uuid) from public,anon;
revoke all on function public.select_delivery_price_offer(uuid) from public,anon;
grant execute on function public.propose_delivery_price(uuid,bigint,text,integer,text) to authenticated;
grant execute on function public.list_delivery_price_offers(uuid) to authenticated;
grant execute on function public.select_delivery_price_offer(uuid) to authenticated;
