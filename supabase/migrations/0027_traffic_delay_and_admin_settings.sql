-- HAITIKET V17 : signalement de retard de circulation + validation des réglages admin.
-- Les prolongations sont des déclarations horodatées, non une garantie de délai.

alter table public.delivery_jobs
  add column if not exists traffic_delay_minutes integer not null default 0,
  add column if not exists traffic_delay_reason text,
  add column if not exists traffic_delay_reported_at timestamptz;

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.delivery_jobs'::regclass
      and conname = 'delivery_jobs_traffic_delay_minutes_check'
  ) then
    alter table public.delivery_jobs
      add constraint delivery_jobs_traffic_delay_minutes_check
      check (traffic_delay_minutes in (0, 120, 240));
  end if;
end $$;

insert into public.platform_settings(key, value) values
  ('shop_fee_yearly_usd', '200'),
  ('payment_provider', 'plopplop'),
  ('delivery_immediate_sla_minutes', '45'),
  ('delivery_traffic_extension_options', '120,240'),
  ('delivery_offer_expiry_minutes', '10')
on conflict (key) do nothing;

create or replace function public.report_delivery_traffic_delay(
  p_job uuid, p_minutes integer, p_reason text
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_job public.delivery_jobs;
  v_options text;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if p_minutes not in (120, 240) then raise exception 'Prolongation autorisée : 2 h ou 4 h'; end if;
  if char_length(trim(coalesce(p_reason, ''))) < 10 or char_length(trim(coalesce(p_reason, ''))) > 500 then
    raise exception 'Le motif doit contenir entre 10 et 500 caractères';
  end if;

  select value into v_options from public.platform_settings where key = 'delivery_traffic_extension_options';
  if v_options is not null and not (p_minutes::text = any(string_to_array(regexp_replace(v_options, '\s', '', 'g'), ','))) then
    raise exception 'Cette prolongation n’est pas autorisée par la configuration';
  end if;

  select * into v_job from public.delivery_jobs where id = p_job for update;
  if v_job.id is null or v_job.courier_id <> v_uid then raise exception 'Mission introuvable ou accès refusé'; end if;
  if v_job.status not in ('assigned', 'picked_up') then raise exception 'Le retard ne peut être signalé que pour une mission en cours'; end if;
  if v_job.traffic_delay_minutes <> 0 or v_job.traffic_delay_reported_at is not null then
    raise exception 'Un retard a déjà été signalé pour cette mission';
  end if;

  update public.delivery_jobs
    set traffic_delay_minutes = p_minutes,
        traffic_delay_reason = trim(p_reason),
        traffic_delay_reported_at = now()
    where id = p_job;

  return true;
end $$;

create or replace function public.get_delivery_traffic_delay(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_job public.delivery_jobs;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  select j.* into v_job
  from public.delivery_jobs j
  join public.orders o on o.id = j.order_id
  where j.order_id = p_order
    and (o.customer_id = v_uid or j.courier_id = v_uid)
  limit 1;
  if v_job.id is null or v_job.traffic_delay_reported_at is null then return null; end if;
  return jsonb_build_object(
    'extension_minutes', v_job.traffic_delay_minutes,
    'reason', v_job.traffic_delay_reason,
    'reported_at', v_job.traffic_delay_reported_at
  );
end $$;

revoke all on function public.report_delivery_traffic_delay(uuid, integer, text) from public, anon;
revoke all on function public.get_delivery_traffic_delay(uuid) from public, anon;
grant execute on function public.report_delivery_traffic_delay(uuid, integer, text) to authenticated;
grant execute on function public.get_delivery_traffic_delay(uuid) to authenticated;


-- L'expiration d'offre est pilotée par le réglage admin (1 à 60 minutes, défaut 10).
create or replace function public.propose_delivery_price(
  p_job uuid, p_amount_minor bigint, p_currency text, p_eta_minutes integer, p_note text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_job public.delivery_jobs; v_lat double precision; v_lng double precision;
  v_updated timestamptz; v_shop_lat double precision; v_shop_lng double precision;
  v_distance double precision; v_id uuid; v_expiry integer := 10;
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

  select greatest(1, least(60, coalesce(value::integer, 10))) into v_expiry
  from public.platform_settings where key = 'delivery_offer_expiry_minutes';
  v_expiry := coalesce(v_expiry, 10);

  insert into public.delivery_job_offers(job_id,courier_id,amount_minor,currency,eta_minutes,note,status,expires_at,updated_at)
  values(p_job,v_uid,p_amount_minor,p_currency,p_eta_minutes,nullif(trim(coalesce(p_note,'')),''),'pending',now()+make_interval(mins => v_expiry),now())
  on conflict(job_id,courier_id) do update set
    amount_minor=excluded.amount_minor, currency=excluded.currency, eta_minutes=excluded.eta_minutes,
    note=excluded.note, status='pending', expires_at=excluded.expires_at, updated_at=now()
  where public.delivery_job_offers.status in ('pending','expired','withdrawn')
  returning id into v_id;
  if v_id is null then raise exception 'Une offre a déjà été sélectionnée ou cette offre ne peut plus être modifiée'; end if;
  return v_id;
end $$;


-- L'interface V15/V16 exposait des réglages que les anciennes listes blanches refusaient.
-- Ce remplacement conserve la vérification admin déverrouillé et journalise chaque changement.
create or replace function public.admin_set_setting(p_key text, p_value text) returns void
language plpgsql security definer set search_path = public as $$
declare v text := trim(coalesce(p_value, ''));
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_key not in (
    'commission_bps','reservation_minutes','delivery_flat_minor','usd_htg_rate',
    'usd_htg_topup_rate','usd_htg_withdraw_rate','bazar_fee_usd','shop_fee_usd',
    'shop_fee_yearly_usd','enforce_shop_plan','referral_reward_minor','payment_provider',
    'delivery_immediate_sla_minutes','delivery_traffic_extension_options',
    'delivery_offer_expiry_minutes'
  ) then raise exception 'Réglage inconnu'; end if;

  if p_key = 'enforce_shop_plan' then
    if v not in ('true','false') then raise exception 'Valeur attendue : true ou false'; end if;
  elsif p_key = 'payment_provider' then
    if v not in ('plopplop','bazik') then raise exception 'Prestataire autorisé : plopplop ou bazik'; end if;
  elsif p_key = 'delivery_traffic_extension_options' then
    if v not in ('120,240','120','240') then raise exception 'Valeurs autorisées : 120, 240 ou 120,240'; end if;
  elsif p_key in ('usd_htg_rate','usd_htg_topup_rate','usd_htg_withdraw_rate','bazar_fee_usd','shop_fee_usd','shop_fee_yearly_usd') then
    if v !~ '^[0-9]{1,6}(\.[0-9]{1,4})?$' or v::numeric <= 0 then raise exception 'Nombre positif requis'; end if;
  else
    if v !~ '^[0-9]{1,9}$' then raise exception 'Nombre entier requis'; end if;
    if p_key in ('delivery_immediate_sla_minutes','reservation_minutes') and v::integer < 1 then
      raise exception 'Une durée positive est requise';
    end if;
    if p_key = 'delivery_offer_expiry_minutes' and v::integer not between 1 and 60 then
      raise exception 'La durée des offres doit être comprise entre 1 et 60 minutes';
    end if;
    if p_key = 'commission_bps' and v::integer > 10000 then raise exception 'La commission ne peut dépasser 100 %'; end if;
  end if;

  insert into public.platform_settings(key, value) values(p_key, v)
  on conflict(key) do update set value = excluded.value, updated_at = now();
  insert into public.admin_audit_logs(actor, action, resource, reason)
  values(auth.uid(), 'set_setting', p_key, left(v, 100));
end $$;
grant execute on function public.admin_set_setting(text, text) to authenticated;
