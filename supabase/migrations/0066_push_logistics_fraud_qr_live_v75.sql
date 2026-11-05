-- HAITIKET V75 — push FCM, centres/tournées, antifraude, QR sécurisé, mentions, alertes livreurs par distance, carte live.
-- À appliquer APRÈS 0065. Idempotent.

-- =====================================================================
-- 1. PUSH : jetons d'appareils (l'envoi est fait par la fonction Edge send-push)
-- =====================================================================
create table if not exists public.push_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'android',
  updated_at timestamptz not null default now()
);
create index if not exists push_tokens_user_idx on public.push_tokens(user_id);
alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon, authenticated;

create or replace function public.register_push_token(p_token text, p_platform text default 'android') returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if char_length(coalesce(p_token,'')) < 20 or char_length(p_token) > 4096 then raise exception 'Jeton invalide'; end if;
  insert into public.push_tokens(token, user_id, platform) values (p_token, auth.uid(), left(coalesce(p_platform,'android'),20))
  on conflict (token) do update set user_id = auth.uid(), platform = excluded.platform, updated_at = now();
end $$;
revoke all on function public.register_push_token(text,text) from public, anon;
grant execute on function public.register_push_token(text,text) to authenticated;

create or replace function public.unregister_push_token(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from public.push_tokens where token = p_token and user_id = auth.uid() $$;
revoke all on function public.unregister_push_token(text) from public, anon;
grant execute on function public.unregister_push_token(text) to authenticated;

-- =====================================================================
-- 2. ALERTES LIVREURS FILTRÉES PAR DISTANCE (réglage courier_alert_radius_km, défaut 15 km)
-- =====================================================================
insert into public.platform_settings(key, value) values ('courier_alert_radius_km','15') on conflict (key) do nothing;

create or replace function public._km(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 6371 * 2 * asin(least(1, sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))) $$;

create or replace function public._trg_new_job() returns trigger language plpgsql security definer set search_path = public as $$
declare v_lat double precision; v_lng double precision; v_radius double precision; v_n integer;
        v_body text := case when new.pay_minor > 0 then 'Rémunération : ' || (new.pay_minor / 100.0)::numeric(12,2) || ' ' || new.currency
                            else 'Proposez votre prix et votre délai : ' || coalesce(new.pickup_area,'') end;
begin
  select s.lat, s.lng into v_lat, v_lng from public.orders o join public.shops s on s.id = o.shop_id where o.id = new.order_id;
  select coalesce(nullif((select value from public.platform_settings where key = 'courier_alert_radius_km'),'')::double precision, 15) into v_radius;

  insert into public.notifications(user_id, kind, title, body, ref)
  select cs.user_id, 'job', 'Nouvelle mission de livraison', v_body, new.id
  from public.courier_status cs
  where cs.available
    and exists (select 1 from public.courier_applications a where a.user_id = cs.user_id and a.status = 'approved')
    and (v_lat is null or cs.lat is null or cs.location_updated_at < now() - interval '30 minutes'
         or public._km(v_lat, v_lng, cs.lat, cs.lng) <= v_radius);
  get diagnostics v_n = row_count;

  -- Personne à proximité : on alerte tous les livreurs disponibles plutôt que de laisser la commande sans réponse.
  if v_n = 0 then
    insert into public.notifications(user_id, kind, title, body, ref)
    select cs.user_id, 'job', 'Nouvelle mission de livraison', v_body, new.id
    from public.courier_status cs
    where cs.available and exists (select 1 from public.courier_applications a where a.user_id = cs.user_id and a.status = 'approved');
  end if;
  return new;
end $$;

-- Précision de la position : 5 décimales (~1 m) pour boutiques pro/officielle, 3 (~100 m) pour les particuliers (confidentialité).
create or replace function public.set_shop_location(p_shop uuid, p_lat double precision, p_lng double precision) returns void
language plpgsql security definer set search_path = public as $$
declare v_kind text;
begin
  if p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'Position invalide'; end if;
  select kind into v_kind from public.shops where id = p_shop and (owner_id = auth.uid() or (is_official and public.admin_unlocked()));
  if v_kind is null then raise exception 'Boutique introuvable'; end if;
  update public.shops set lat = round(p_lat::numeric, case when v_kind in ('pro','platform') then 5 else 3 end),
                          lng = round(p_lng::numeric, case when v_kind in ('pro','platform') then 5 else 3 end)
  where id = p_shop;
end $$;
grant execute on function public.set_shop_location(uuid, double precision, double precision) to authenticated;

-- =====================================================================
-- 3. MENTIONS DANS LA MESSAGERIE (@prénom ou @tous)
-- =====================================================================
create or replace function public._trg_message_mentions() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if position('@' in new.body) = 0 then return new; end if;
  insert into public.notifications(user_id, kind, title, body, ref)
  select m.user_id, 'mention', 'Vous avez été mentionné', left(new.body, 200), new.conversation_id
  from public.conversation_members m
  join public.profiles p on p.id = m.user_id
  where m.conversation_id = new.conversation_id and m.user_id <> new.sender_id
    and (new.body ilike '%@tous%'
         or (coalesce(split_part(trim(p.display_name),' ',1),'') <> '' and new.body ilike '%@' || split_part(trim(p.display_name),' ',1) || '%'));
  return new;
end $$;
drop trigger if exists messages_mentions on public.messages;
create trigger messages_mentions after insert on public.messages for each row execute function public._trg_message_mentions();

-- =====================================================================
-- 4. QR SÉCURISÉ : charge utile « HKT1:<commande>:<code> » (aucune donnée personnelle), vérifiée par le serveur et journalisée
-- =====================================================================
create table if not exists public.qr_scan_log (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references public.delivery_jobs(id) on delete set null,
  order_id uuid, actor uuid, kind text not null, success boolean not null,
  created_at timestamptz not null default now()
);
alter table public.qr_scan_log enable row level security;
revoke all on public.qr_scan_log from anon, authenticated;

create or replace function public._qr_scan(p_job uuid, p_payload text, p_kind text) returns boolean
language plpgsql security definer set search_path = public as $$
declare parts text[]; v_order uuid; j public.delivery_jobs; ok boolean;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  parts := string_to_array(trim(coalesce(p_payload,'')), ':');
  if coalesce(array_length(parts,1),0) <> 3 or parts[1] <> 'HKT1' then raise exception 'QR HAITIKET invalide'; end if;
  begin v_order := parts[2]::uuid; exception when others then raise exception 'QR HAITIKET invalide'; end;
  select * into j from public.delivery_jobs where id = p_job and courier_id = auth.uid();
  if j.id is null then raise exception 'Mission introuvable ou non attribuée à ce coursier'; end if;
  if j.order_id <> v_order then
    update public.delivery_jobs set failed = failed + 1 where id = p_job;
    insert into public.qr_scan_log(job_id, order_id, actor, kind, success) values (p_job, v_order, auth.uid(), p_kind, false);
    return false;
  end if;
  if p_kind = 'pickup' then ok := public.confirm_pickup(p_job, parts[3]); else ok := public.confirm_delivery(p_job, parts[3]); end if;
  insert into public.qr_scan_log(job_id, order_id, actor, kind, success) values (p_job, v_order, auth.uid(), p_kind, coalesce(ok,false));
  return coalesce(ok,false);
end $$;
revoke all on function public._qr_scan(uuid,text,text) from public, anon, authenticated;

create or replace function public.confirm_pickup_qr(p_job uuid, p_payload text) returns boolean
language sql security definer set search_path = public as $$ select public._qr_scan(p_job, p_payload, 'pickup') $$;
create or replace function public.confirm_delivery_qr(p_job uuid, p_payload text) returns boolean
language sql security definer set search_path = public as $$ select public._qr_scan(p_job, p_payload, 'delivery') $$;
revoke all on function public.confirm_pickup_qr(uuid,text) from public, anon;
revoke all on function public.confirm_delivery_qr(uuid,text) from public, anon;
grant execute on function public.confirm_pickup_qr(uuid,text) to authenticated;
grant execute on function public.confirm_delivery_qr(uuid,text) to authenticated;

-- =====================================================================
-- 5. CENTRES LOGISTIQUES, TOURNÉES MULTI-COMMANDES, SCANS (cahier §14)
-- =====================================================================
create table if not exists public.logistics_centers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 80),
  kind text not null default 'center' check (kind in ('center','pickup_point','partner')),
  city text, address text, zone text,
  lat double precision, lng double precision,
  capacity integer not null default 50 check (capacity between 1 and 5000),
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create table if not exists public.delivery_tours (
  id uuid primary key default gen_random_uuid(),
  center_id uuid references public.logistics_centers(id),
  courier_id uuid not null references auth.users(id),
  status text not null default 'planned' check (status in ('planned','active','completed','cancelled')),
  capacity integer not null default 8 check (capacity between 1 and 50),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(), started_at timestamptz, completed_at timestamptz
);
create table if not exists public.tour_stops (
  id uuid primary key default gen_random_uuid(),
  tour_id uuid not null references public.delivery_tours(id) on delete cascade,
  job_id uuid not null unique references public.delivery_jobs(id),
  seq integer not null,
  created_at timestamptz not null default now(),
  unique (tour_id, seq)
);
create table if not exists public.center_scans (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.logistics_centers(id),
  order_id uuid references public.orders(id),
  event text not null check (event in ('received','dispatched','returned','incident')),
  note text, actor uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.logistics_centers enable row level security;
alter table public.delivery_tours enable row level security;
alter table public.tour_stops enable row level security;
alter table public.center_scans enable row level security;
revoke all on public.logistics_centers, public.delivery_tours, public.tour_stops, public.center_scans from anon, authenticated;

create or replace function public.admin_upsert_center(p_id uuid, p_name text, p_kind text, p_city text, p_address text, p_zone text,
  p_lat double precision, p_lng double precision, p_capacity integer, p_active boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_kind not in ('center','pickup_point','partner') then raise exception 'Type invalide'; end if;
  if p_lat is not null and p_lat not between -90 and 90 then raise exception 'Latitude invalide'; end if;
  if p_lng is not null and p_lng not between -180 and 180 then raise exception 'Longitude invalide'; end if;
  if p_id is null then
    insert into public.logistics_centers(name,kind,city,address,zone,lat,lng,capacity,active,created_by)
    values (trim(p_name),p_kind,nullif(trim(coalesce(p_city,'')),''),nullif(trim(coalesce(p_address,'')),''),nullif(trim(coalesce(p_zone,'')),''),p_lat,p_lng,greatest(1,coalesce(p_capacity,50)),coalesce(p_active,true),auth.uid()) returning id into v;
  else
    update public.logistics_centers set name=trim(p_name),kind=p_kind,city=nullif(trim(coalesce(p_city,'')),''),address=nullif(trim(coalesce(p_address,'')),''),
      zone=nullif(trim(coalesce(p_zone,'')),''),lat=p_lat,lng=p_lng,capacity=greatest(1,coalesce(p_capacity,50)),active=coalesce(p_active,true) where id=p_id returning id into v;
    if v is null then raise exception 'Centre introuvable'; end if;
  end if;
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason) values (auth.uid(),'upsert_center','logistics_center',v,left(trim(p_name),200));
  return v;
end $$;
revoke all on function public.admin_upsert_center(uuid,text,text,text,text,text,double precision,double precision,integer,boolean) from public, anon;
grant execute on function public.admin_upsert_center(uuid,text,text,text,text,text,double precision,double precision,integer,boolean) to authenticated;

create or replace function public.admin_list_centers() returns setof public.logistics_centers
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query select * from public.logistics_centers order by active desc, name;
end $$;
revoke all on function public.admin_list_centers() from public, anon;
grant execute on function public.admin_list_centers() to authenticated;

create or replace function public.admin_create_tour(p_center uuid, p_courier uuid, p_capacity integer, p_notes text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if not exists(select 1 from public.courier_applications where user_id = p_courier and status = 'approved') then raise exception 'Ce livreur n''est pas approuvé'; end if;
  if p_center is not null and not exists(select 1 from public.logistics_centers where id = p_center and active) then raise exception 'Centre inactif ou introuvable'; end if;
  insert into public.delivery_tours(center_id,courier_id,capacity,notes,created_by) values (p_center,p_courier,least(50,greatest(1,coalesce(p_capacity,8))),nullif(trim(coalesce(p_notes,'')),''),auth.uid()) returning id into v;
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason) values (auth.uid(),'create_tour','delivery_tour',v,'tournée créée');
  return v;
end $$;
revoke all on function public.admin_create_tour(uuid,uuid,integer,text) from public, anon;
grant execute on function public.admin_create_tour(uuid,uuid,integer,text) to authenticated;

-- Une commande n'entre dans une tournée que si sa mission est attribuée AU MÊME livreur et pas encore collectée.
create or replace function public.admin_add_tour_stop(p_tour uuid, p_order uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t public.delivery_tours; j public.delivery_jobs; n integer;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  select * into t from public.delivery_tours where id = p_tour for update;
  if t.id is null then raise exception 'Tournée introuvable'; end if;
  if t.status not in ('planned','active') then raise exception 'Tournée terminée ou annulée'; end if;
  select * into j from public.delivery_jobs where order_id = p_order;
  if j.id is null then raise exception 'Aucune mission de livraison pour cette commande'; end if;
  if j.status <> 'assigned' or j.courier_id is distinct from t.courier_id then raise exception 'La mission doit être attribuée au livreur de cette tournée et non collectée'; end if;
  select count(*) into n from public.tour_stops where tour_id = p_tour;
  if n >= t.capacity then raise exception 'Capacité de la tournée atteinte (%)', t.capacity; end if;
  insert into public.tour_stops(tour_id, job_id, seq) values (p_tour, j.id, n + 1);
exception when unique_violation then raise exception 'Cette commande est déjà dans une tournée';
end $$;
revoke all on function public.admin_add_tour_stop(uuid,uuid) from public, anon;
grant execute on function public.admin_add_tour_stop(uuid,uuid) to authenticated;

create or replace function public.admin_set_tour_status(p_tour uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
declare t public.delivery_tours; pending integer;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_status not in ('active','completed','cancelled') then raise exception 'Statut invalide'; end if;
  select * into t from public.delivery_tours where id = p_tour for update;
  if t.id is null then raise exception 'Tournée introuvable'; end if;
  if t.status in ('completed','cancelled') then raise exception 'Tournée déjà clôturée'; end if;
  if p_status = 'completed' then
    select count(*) into pending from public.tour_stops s join public.delivery_jobs j on j.id = s.job_id where s.tour_id = p_tour and j.status in ('open','assigned','picked_up');
    if pending > 0 then raise exception '% arrêt(s) ne sont pas terminés', pending; end if;
  end if;
  update public.delivery_tours set status = p_status,
    started_at = case when p_status = 'active' then now() else started_at end,
    completed_at = case when p_status in ('completed','cancelled') then now() else completed_at end where id = p_tour;
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason) values (auth.uid(),'tour_'||p_status,'delivery_tour',p_tour,'changement de statut');
end $$;
revoke all on function public.admin_set_tour_status(uuid,text) from public, anon;
grant execute on function public.admin_set_tour_status(uuid,text) to authenticated;

create or replace function public.admin_list_tours(p_status text default 'all') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return coalesce((select jsonb_agg(x order by x.created_at desc) from (
    select t.id, t.status, t.capacity, t.notes, t.created_at, t.started_at, t.completed_at,
           c.name as center_name, p.display_name as courier_name,
           (select count(*) from public.tour_stops s where s.tour_id = t.id) as stops,
           (select count(*) from public.tour_stops s join public.delivery_jobs j on j.id = s.job_id where s.tour_id = t.id and j.status = 'delivered') as delivered,
           coalesce((select jsonb_agg(jsonb_build_object('seq',s.seq,'order_id',j.order_id,'job_status',j.status,'dropoff',j.dropoff_address) order by s.seq)
                     from public.tour_stops s join public.delivery_jobs j on j.id = s.job_id where s.tour_id = t.id), '[]'::jsonb) as items
    from public.delivery_tours t
    left join public.logistics_centers c on c.id = t.center_id
    left join public.profiles p on p.id = t.courier_id
    where p_status = 'all' or t.status = p_status
    order by t.created_at desc limit 60) x), '[]'::jsonb);
end $$;
revoke all on function public.admin_list_tours(text) from public, anon;
grant execute on function public.admin_list_tours(text) to authenticated;

create or replace function public.admin_center_scan(p_center uuid, p_order uuid, p_event text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_event not in ('received','dispatched','returned','incident') then raise exception 'Événement invalide'; end if;
  if not exists(select 1 from public.logistics_centers where id = p_center) then raise exception 'Centre introuvable'; end if;
  if p_order is not null and not exists(select 1 from public.orders where id = p_order) then raise exception 'Commande introuvable'; end if;
  insert into public.center_scans(center_id, order_id, event, note, actor) values (p_center, p_order, p_event, nullif(trim(coalesce(p_note,'')),''), auth.uid());
end $$;
revoke all on function public.admin_center_scan(uuid,uuid,text,text) from public, anon;
grant execute on function public.admin_center_scan(uuid,uuid,text,text) to authenticated;

create or replace function public.admin_list_center_scans(p_center uuid default null) returns table(id uuid, center_name text, order_id uuid, event text, note text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query select s.id, c.name, s.order_id, s.event, s.note, s.created_at from public.center_scans s join public.logistics_centers c on c.id = s.center_id
    where p_center is null or s.center_id = p_center order by s.created_at desc limit 80;
end $$;
revoke all on function public.admin_list_center_scans(uuid) from public, anon;
grant execute on function public.admin_list_center_scans(uuid) to authenticated;

-- Côté livreur : mes tournées actives avec leurs arrêts
create or replace function public.my_tours() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  return coalesce((select jsonb_agg(x order by x.created_at desc) from (
    select t.id, t.status, t.notes, t.created_at, c.name as center_name, c.address as center_address,
      coalesce((select jsonb_agg(jsonb_build_object('seq',s.seq,'job_id',j.id,'job_status',j.status,'dropoff',j.dropoff_address) order by s.seq)
                from public.tour_stops s join public.delivery_jobs j on j.id = s.job_id where s.tour_id = t.id), '[]'::jsonb) as items
    from public.delivery_tours t left join public.logistics_centers c on c.id = t.center_id
    where t.courier_id = auth.uid() and t.status in ('planned','active')) x), '[]'::jsonb);
end $$;
revoke all on function public.my_tours() from public, anon;
grant execute on function public.my_tours() to authenticated;

-- =====================================================================
-- 6. ANTIFRAUDE AUTOMATIQUE (cahier §22) : détection + examen manuel (aucun blocage automatique)
-- =====================================================================
create table if not exists public.fraud_alerts (
  id uuid primary key default gen_random_uuid(),
  kind text not null, severity text not null default 'medium' check (severity in ('low','medium','high')),
  user_id uuid, order_id uuid, detail text,
  status text not null default 'open' check (status in ('open','reviewed','dismissed')),
  dedupe_key text not null unique,
  note text, reviewed_by uuid, reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.fraud_alerts enable row level security;
revoke all on public.fraud_alerts from anon, authenticated;

create or replace function public.run_fraud_scan() returns integer
language plpgsql security definer set search_path = public as $$
declare total integer := 0; n integer;
begin
  -- Doubles paiements : plusieurs achats réussis pour la même référence
  insert into public.fraud_alerts(kind, severity, user_id, detail, dedupe_key)
  select 'double_payment', 'high', min(t.user_id::text)::uuid, 'Référence ' || t.reference || ' : ' || count(*) || ' paiements réussis', 'dup:' || t.reference
  from public.wallet_transactions t where t.kind = 'purchase' and t.status = 'successful' and t.reference is not null
  group by t.reference having count(*) > 1
  on conflict (dedupe_key) do nothing;
  get diagnostics n = row_count; total := total + n;

  -- Abus de coupons : 5 utilisations ou plus en 24 h
  insert into public.fraud_alerts(kind, severity, user_id, detail, dedupe_key)
  select 'coupon_abuse', 'medium', r.user_id, count(*) || ' coupons utilisés en 24 h', 'coupon:' || r.user_id || ':' || current_date
  from public.coupon_redemptions r where r.created_at > now() - interval '24 hours'
  group by r.user_id having count(*) >= 5
  on conflict (dedupe_key) do nothing;
  get diagnostics n = row_count; total := total + n;

  -- Abus de parrainage : 5 filleuls ou plus en 24 h pour un même parrain
  insert into public.fraud_alerts(kind, severity, user_id, detail, dedupe_key)
  select 'referral_abuse', 'medium', p.referred_by, count(*) || ' filleuls inscrits en 24 h', 'ref:' || p.referred_by || ':' || current_date
  from public.profiles p where p.referred_by is not null and p.created_at > now() - interval '24 hours'
  group by p.referred_by having count(*) >= 5
  on conflict (dedupe_key) do nothing;
  get diagnostics n = row_count; total := total + n;

  -- Abus de remboursement : 3 demandes ou plus en 30 jours
  insert into public.fraud_alerts(kind, severity, user_id, detail, dedupe_key)
  select 'refund_abuse', 'high', r.user_id, count(*) || ' remboursements en 30 jours', 'refund:' || r.user_id || ':' || to_char(current_date, 'IYYY-IW')
  from public.refund_requests r where r.created_at > now() - interval '30 days'
  group by r.user_id having count(*) >= 3
  on conflict (dedupe_key) do nothing;
  get diagnostics n = row_count; total := total + n;

  -- Codes de livraison/collecte erronés à répétition
  insert into public.fraud_alerts(kind, severity, user_id, order_id, detail, dedupe_key)
  select 'pin_failures', 'high', j.courier_id, j.order_id, j.failed || ' codes erronés sur la mission', 'pin:' || j.id
  from public.delivery_jobs j where j.failed >= 3
  on conflict (dedupe_key) do nothing;
  get diagnostics n = row_count; total := total + n;
  return total;
end $$;
revoke all on function public.run_fraud_scan() from public, anon, authenticated;

create or replace function public.admin_run_fraud_scan() returns integer
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return public.run_fraud_scan();
end $$;
revoke all on function public.admin_run_fraud_scan() from public, anon;
grant execute on function public.admin_run_fraud_scan() to authenticated;

create or replace function public.admin_list_fraud_alerts(p_status text default 'open') returns table(
  id uuid, kind text, severity text, user_id uuid, user_name text, order_id uuid, detail text, status text, note text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query select a.id, a.kind, a.severity, a.user_id, p.display_name, a.order_id, a.detail, a.status, a.note, a.created_at
    from public.fraud_alerts a left join public.profiles p on p.id = a.user_id
    where p_status = 'all' or a.status = p_status order by (a.severity = 'high') desc, a.created_at desc limit 100;
end $$;
revoke all on function public.admin_list_fraud_alerts(text) from public, anon;
grant execute on function public.admin_list_fraud_alerts(text) to authenticated;

create or replace function public.admin_review_fraud_alert(p_alert uuid, p_status text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_status not in ('reviewed','dismissed') then raise exception 'Statut invalide'; end if;
  update public.fraud_alerts set status = p_status, note = left(coalesce(p_note,''),500), reviewed_by = auth.uid(), reviewed_at = now() where id = p_alert;
  if not found then raise exception 'Alerte introuvable'; end if;
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason) values (auth.uid(),'fraud_'||p_status,'fraud_alert',p_alert,left(coalesce(p_note,''),200));
end $$;
revoke all on function public.admin_review_fraud_alert(uuid,text,text) from public, anon;
grant execute on function public.admin_review_fraud_alert(uuid,text,text) to authenticated;

do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('haitiket-fraud-scan', '*/15 * * * *', 'select public.run_fraud_scan()');
exception when others then raise notice 'pg_cron indisponible : utilisez le bouton « Lancer l''analyse » de l''admin'; end $$;

-- =====================================================================
-- 7. CARTE LIVE ADMIN : livreurs, missions, livraisons en cours, boutiques (actualisée par l'application toutes les 10 s)
-- =====================================================================
create or replace function public.admin_live_map() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return jsonb_build_object(
    'couriers', coalesce((select jsonb_agg(jsonb_build_object('id',cs.user_id,'name',coalesce(p.display_name,'Livreur'),'lat',cs.lat,'lng',cs.lng,'available',cs.available,
        'age_s', extract(epoch from (now() - cs.location_updated_at))::int,
        'on_job', exists(select 1 from public.delivery_jobs j where j.courier_id = cs.user_id and j.status in ('assigned','picked_up'))))
      from public.courier_status cs left join public.profiles p on p.id = cs.user_id
      where cs.lat is not null and cs.location_updated_at > now() - interval '20 minutes'), '[]'::jsonb),
    'open_jobs', coalesce((select jsonb_agg(jsonb_build_object('id',j.id,'order_id',j.order_id,'area',j.pickup_area,'lat',s.lat,'lng',s.lng,'age_min',extract(epoch from (now() - j.created_at))::int / 60))
      from public.delivery_jobs j join public.orders o on o.id = j.order_id join public.shops s on s.id = o.shop_id where j.status = 'open'), '[]'::jsonb),
    'deliveries', coalesce((select jsonb_agg(jsonb_build_object('order_id',o.id,'status',j.status,'lat',o.delivery_lat,'lng',o.delivery_lng,'address',j.dropoff_address))
      from public.delivery_jobs j join public.orders o on o.id = j.order_id where j.status in ('assigned','picked_up') and o.delivery_lat is not null), '[]'::jsonb),
    'shops', coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'kind',s.kind,'lat',s.lat,'lng',s.lng)) from public.shops s where s.status = 'active' and s.lat is not null), '[]'::jsonb),
    'centers', coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'lat',c.lat,'lng',c.lng)) from public.logistics_centers c where c.active and c.lat is not null), '[]'::jsonb),
    'at', now());
end $$;
revoke all on function public.admin_live_map() from public, anon;
grant execute on function public.admin_live_map() to authenticated;

-- Liste des livreurs approuvés (pour créer une tournée)
create or replace function public.admin_list_couriers() returns table(user_id uuid, full_name text, phone text, zone text, available boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query select a.user_id, a.full_name, a.phone, a.zone, coalesce(cs.available,false)
    from public.courier_applications a left join public.courier_status cs on cs.user_id = a.user_id
    where a.status = 'approved' order by a.full_name;
end $$;
revoke all on function public.admin_list_couriers() from public, anon;
grant execute on function public.admin_list_couriers() to authenticated;
