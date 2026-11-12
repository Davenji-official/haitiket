-- HAITIKET V80 — livraison : missions visibles, contacts/adresse obligatoires, type d'adresse, livraison immédiate
-- (prix fixé par le vendeur), fiche complète de commande, diagnostic livreur. À appliquer APRÈS 0070. Idempotent.

-- =====================================================================
-- 1. MISSIONS : fiabilité (création dès le paiement, position boutique facultative, GPS 10 min)
-- =====================================================================
insert into public.platform_settings(key, value) values ('courier_gps_max_minutes','10') on conflict (key) do nothing;
create or replace function public._gps_max_age() returns interval language sql stable security definer set search_path = public as $$
  select make_interval(mins => greatest(1, least(60, coalesce((select nullif(value,'')::int from public.platform_settings where key = 'courier_gps_max_minutes'), 10)))) $$;
revoke all on function public._gps_max_age() from public, anon;
grant execute on function public._gps_max_age() to authenticated;

-- Distance en km (formule de haversine) — fonction utilitaire
create or replace function public._km(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 6371 * 2 * asin(least(1, sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))) $$;

-- Colonnes de livraison détaillée
alter table public.orders add column if not exists delivery_kind text;
alter table public.orders add column if not exists delivery_landmark text;
alter table public.orders add column if not exists delivery_recipient text;
alter table public.orders add column if not exists delivery_phone text;
alter table public.orders add column if not exists delivery_whatsapp text;
alter table public.orders add column if not exists delivery_speed text not null default 'standard';
alter table public.orders add column if not exists promised_minutes integer;
alter table public.orders drop constraint if exists orders_delivery_speed_check;
alter table public.orders add constraint orders_delivery_speed_check check (delivery_speed in ('immediate','standard'));
alter table public.orders drop constraint if exists orders_delivery_kind_check;
alter table public.orders add constraint orders_delivery_kind_check check (delivery_kind is null or delivery_kind in ('home','precise','meeting_point','school','work','other','pickup','center'));

-- Réglages de préparation / livraison immédiate par boutique (fixés par le vendeur)
alter table public.shops add column if not exists prep_minutes integer not null default 30;
alter table public.shops add column if not exists immediate_delivery_enabled boolean not null default true;
alter table public.shops add column if not exists immediate_fee_htg_minor bigint;
alter table public.shops add column if not exists immediate_fee_usd_minor bigint;
alter table public.shops drop constraint if exists shops_prep_minutes_check;
alter table public.shops add constraint shops_prep_minutes_check check (prep_minutes between 1 and 1440);
alter table public.products add column if not exists prep_minutes integer;
alter table public.products add column if not exists immediate_ok boolean not null default true;

create or replace function public.create_delivery_job(p_order uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare o public.orders; v_area text; jid uuid;
begin
  select id into jid from public.delivery_jobs where order_id = p_order;
  if jid is not null then return jid; end if;
  select * into o from public.orders where id = p_order;
  if o.id is null or o.delivery_mode <> 'delivery' or o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') then
    raise exception 'Commande non éligible à une mission';
  end if;
  select s.name || coalesce(' · ' || s.city, '') into v_area from public.shops s where s.id = o.shop_id;
  insert into public.delivery_jobs(order_id, pickup_area, dropoff_address, pay_minor, currency, pickup_pin)
  values (o.id, coalesce(v_area, 'Zone non précisée'), coalesce(nullif(trim(o.delivery_address),''), 'Adresse à préciser avec le client'), o.delivery_minor, o.currency, public._gen_pin())
  on conflict (order_id) do nothing returning id into jid;
  if jid is null then select id into jid from public.delivery_jobs where order_id = p_order; end if;
  return jid;
end $$;
revoke all on function public.create_delivery_job(uuid) from public, anon, authenticated;

-- La mission est créée DÈS LE PAIEMENT (cahier §13 : « rechercher les livreurs éligibles/disponibles ; envoyer une mission »),
-- et non plus seulement quand le vendeur confirme.
create or replace function public._trg_order_paid_job() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'PAID' and old.status is distinct from 'PAID' and new.delivery_mode = 'delivery' then
    begin
      perform public.create_delivery_job(new.id);
    exception when others then
      raise warning 'create_delivery_job a échoué pour la commande % : %', new.id, sqlerrm;
    end;
  end if;
  return new;
end $$;
drop trigger if exists orders_paid_job on public.orders;
create trigger orders_paid_job after update of status on public.orders for each row execute function public._trg_order_paid_job();

-- Rattrapage : commandes déjà payées en livraison sans mission
do $$
declare r record;
begin
  for r in select o.id from public.orders o where o.delivery_mode = 'delivery' and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP')
           and not exists (select 1 from public.delivery_jobs j where j.order_id = o.id) loop
    begin perform public.create_delivery_job(r.id); exception when others then raise notice 'rattrapage % : %', r.id, sqlerrm; end;
  end loop;
end $$;

-- Liste des missions ouvertes pour le livreur (position boutique facultative ; GPS 10 min ; rayon 25 km seulement si positions connues)
create or replace function public.list_open_jobs_v80()
returns table(id uuid, order_id uuid, pickup_area text, pay_minor bigint, currency text, created_at timestamptz,
              delivery_kind text, delivery_speed text, promised_minutes integer, items_count bigint, items_preview text, distance_km numeric, shop_name text)
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_lat double precision; v_lng double precision; v_updated timestamptz;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not public._is_approved_courier() then raise exception 'Candidature non approuvée'; end if;
  select cs.lat, cs.lng, cs.location_updated_at into v_lat, v_lng, v_updated from public.courier_status cs where cs.user_id = v_uid and cs.available = true;
  if v_lat is null or v_lng is null or v_updated is null or v_updated < now() - public._gps_max_age() then return; end if;
  return query
  select j.id, j.order_id, j.pickup_area, j.pay_minor, j.currency, j.created_at,
         o.delivery_kind, o.delivery_speed, o.promised_minutes,
         (select count(*) from public.order_items i where i.order_id = o.id),
         (select string_agg(i.qty || '× ' || i.name, ', ') from public.order_items i where i.order_id = o.id),
         case when s.lat is null or s.lng is null then null else round(public._km(s.lat, s.lng, v_lat, v_lng)::numeric, 1) end,
         s.name
  from public.delivery_jobs j
  join public.orders o on o.id = j.order_id
  join public.shops s on s.id = o.shop_id
  where j.status = 'open' and o.delivery_mode = 'delivery'
    and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') and s.status = 'active'
    and (s.lat is null or s.lng is null or public._km(s.lat, s.lng, v_lat, v_lng) <= 25.0)
  order by j.created_at desc limit 50;
end $$;
revoke all on function public.list_open_jobs_v80() from public, anon;
grant execute on function public.list_open_jobs_v80() to authenticated;

-- Diagnostic : pourquoi je ne vois aucune mission ?
create or replace function public.courier_mission_diagnostic() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); cs public.courier_status; v_open int; v_nopos int; v_far int := 0; v_age int;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  select * into cs from public.courier_status where user_id = v_uid;
  v_age := case when cs.location_updated_at is null then null else extract(epoch from (now() - cs.location_updated_at))::int end;
  select count(*) into v_open from public.delivery_jobs j join public.orders o on o.id = j.order_id join public.shops s on s.id = o.shop_id
    where j.status = 'open' and o.delivery_mode = 'delivery' and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') and s.status = 'active';
  select count(*) into v_nopos from public.delivery_jobs j join public.orders o on o.id = j.order_id join public.shops s on s.id = o.shop_id
    where j.status = 'open' and (s.lat is null or s.lng is null);
  if cs.lat is not null then
    select count(*) into v_far from public.delivery_jobs j join public.orders o on o.id = j.order_id join public.shops s on s.id = o.shop_id
      where j.status = 'open' and s.lat is not null and s.lng is not null and public._km(s.lat, s.lng, cs.lat, cs.lng) > 25.0;
  end if;
  return jsonb_build_object('approved', public._is_approved_courier(), 'available', coalesce(cs.available,false), 'has_gps', cs.lat is not null,
    'gps_age_s', v_age, 'gps_max_s', extract(epoch from public._gps_max_age())::int, 'open_jobs_total', v_open,
    'open_jobs_shop_without_position', v_nopos, 'open_jobs_out_of_radius', v_far);
end $$;
revoke all on function public.courier_mission_diagnostic() from public, anon;
grant execute on function public.courier_mission_diagnostic() to authenticated;

-- =====================================================================
-- 2. CONTACTS ET ADRESSE OBLIGATOIRES + TYPE D'ADRESSE + LIVRAISON IMMÉDIATE
-- =====================================================================
create or replace function public.set_order_delivery_details(
  p_order uuid, p_kind text, p_landmark text, p_recipient text, p_phone text, p_whatsapp text, p_speed text default 'standard')
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; s public.shops; v_phone text; v_wa text; v_fee bigint; v_prom integer; v_sla integer := 45;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into o from public.orders where id = p_order for update;
  if o.id is null or o.customer_id <> auth.uid() then raise exception 'Commande introuvable ou accès refusé'; end if;
  if o.status <> 'PENDING_PAYMENT' then raise exception 'Les détails ne peuvent plus être modifiés après le paiement'; end if;
  v_phone := nullif(regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g'), '');
  v_wa := nullif(regexp_replace(coalesce(p_whatsapp,''), '[^0-9+]', '', 'g'), '');
  if v_phone is null or length(v_phone) < 8 then raise exception 'Numéro d''appel obligatoire'; end if;
  if v_wa is null or length(v_wa) < 8 then raise exception 'Numéro WhatsApp obligatoire'; end if;
  select * into s from public.shops where id = o.shop_id;
  if o.delivery_mode = 'delivery' then
    if p_kind not in ('home','precise','meeting_point','school','work','other') then raise exception 'Type d''adresse de livraison obligatoire'; end if;
    if char_length(btrim(coalesce(o.delivery_address,''))) < 5 then raise exception 'Adresse de livraison obligatoire'; end if;
  end if;
  if p_speed not in ('immediate','standard') then raise exception 'Mode de livraison invalide'; end if;
  if p_speed = 'immediate' and o.delivery_mode = 'delivery' and not s.immediate_delivery_enabled then raise exception 'Cette boutique ne propose pas la livraison immédiate'; end if;
  if p_speed = 'immediate' and exists (select 1 from public.order_items i join public.products p on p.id = i.product_id where i.order_id = o.id and not p.immediate_ok) then
    raise exception 'Un article de la commande n''est pas disponible en immédiat';
  end if;

  select coalesce(nullif(value,'')::int, 45) into v_sla from public.platform_settings where key = 'delivery_immediate_sla_minutes';
  v_prom := case when p_speed = 'immediate' then coalesce(v_sla, 45)
                 else coalesce((select max(coalesce(p.prep_minutes, s.prep_minutes)) from public.order_items i join public.products p on p.id = i.product_id where i.order_id = o.id), s.prep_minutes, 30) end;

  -- Prix de livraison immédiate fixé par le vendeur (sinon : offres des livreurs)
  v_fee := case when p_speed = 'immediate' and o.delivery_mode = 'delivery' then (case when o.currency = 'USD' then s.immediate_fee_usd_minor else s.immediate_fee_htg_minor end) else null end;
  update public.orders set
    delivery_kind = case when o.delivery_mode = 'delivery' then p_kind else 'pickup' end,
    delivery_landmark = nullif(left(trim(coalesce(p_landmark,'')),300),''),
    delivery_recipient = nullif(left(trim(coalesce(p_recipient,'')),80),''),
    delivery_phone = v_phone, delivery_whatsapp = v_wa, delivery_speed = p_speed, promised_minutes = v_prom
  where id = o.id;
  if v_fee is not null and v_fee > 0 then
    update public.orders set total_minor = total_minor - delivery_minor + v_fee, delivery_minor = v_fee where id = o.id;
  end if;
  -- Mémorise les coordonnées dans le profil si elles manquent
  update public.profiles set phone = coalesce(nullif(phone,''), v_phone), whatsapp = coalesce(nullif(whatsapp,''), v_wa) where id = auth.uid();
  return jsonb_build_object('delivery_minor', coalesce(v_fee, o.delivery_minor), 'fixed_fee', coalesce(v_fee > 0, false), 'promised_minutes', v_prom, 'speed', p_speed);
end $$;
revoke all on function public.set_order_delivery_details(uuid,text,text,text,text,text,text) from public, anon;
grant execute on function public.set_order_delivery_details(uuid,text,text,text,text,text,text) to authenticated;

-- Garde serveur : une commande ne peut pas être payée sans numéro d'appel, WhatsApp et (en livraison) adresse.
create or replace function public._trg_order_contact_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  if new.status = 'PAID' and old.status is distinct from 'PAID' then
    select * into p from public.profiles where id = new.customer_id;
    new.delivery_phone := coalesce(nullif(new.delivery_phone,''), nullif(p.phone,''));
    new.delivery_whatsapp := coalesce(nullif(new.delivery_whatsapp,''), nullif(p.whatsapp,''));
    if new.delivery_phone is null or new.delivery_whatsapp is null then
      raise exception 'Numéro d''appel et WhatsApp obligatoires : complétez-les avant de payer (Profil ou écran de commande).';
    end if;
    if new.delivery_mode = 'delivery' and char_length(btrim(coalesce(new.delivery_address,''))) < 5 then
      raise exception 'Adresse de livraison obligatoire avant le paiement.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists orders_contact_guard on public.orders;
create trigger orders_contact_guard before update of status on public.orders for each row execute function public._trg_order_contact_guard();

-- Vendeur : délai de préparation et livraison immédiate
create or replace function public.seller_set_delivery_settings(p_shop uuid, p_prep_minutes integer, p_immediate boolean, p_fee_htg_minor bigint, p_fee_usd_minor bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if p_prep_minutes is null or p_prep_minutes < 1 or p_prep_minutes > 1440 then raise exception 'Délai de préparation invalide (1 à 1440 minutes)'; end if;
  if (p_fee_htg_minor is not null and p_fee_htg_minor < 0) or (p_fee_usd_minor is not null and p_fee_usd_minor < 0) then raise exception 'Prix invalide'; end if;
  update public.shops set prep_minutes = p_prep_minutes, immediate_delivery_enabled = coalesce(p_immediate, true),
    immediate_fee_htg_minor = nullif(p_fee_htg_minor, 0), immediate_fee_usd_minor = nullif(p_fee_usd_minor, 0)
  where id = p_shop and owner_id = auth.uid();
  if not found then raise exception 'Boutique introuvable ou accès refusé'; end if;
end $$;
revoke all on function public.seller_set_delivery_settings(uuid,integer,boolean,bigint,bigint) from public, anon;
grant execute on function public.seller_set_delivery_settings(uuid,integer,boolean,bigint,bigint) to authenticated;

-- Livreur : accepter une mission au prix fixé par le vendeur (livraison immédiate à prix imposé), attribution atomique
create or replace function public.accept_fixed_price_job(p_job uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); j public.delivery_jobs; o public.orders; cs public.courier_status;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not public._is_approved_courier() then raise exception 'Candidature non approuvée'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));
  select * into cs from public.courier_status where user_id = v_uid and available = true for update;
  if cs.lat is null or cs.location_updated_at is null or cs.location_updated_at < now() - public._gps_max_age() then raise exception 'Position GPS absente ou trop ancienne : actualisez votre position'; end if;
  select * into j from public.delivery_jobs where id = p_job for update;
  if j.id is null or j.status <> 'open' then raise exception 'Mission déjà prise ou indisponible'; end if;
  select * into o from public.orders where id = j.order_id for update;
  if o.delivery_speed <> 'immediate' or o.delivery_minor <= 0 or j.pay_minor <> o.delivery_minor then raise exception 'Cette mission n''a pas de prix fixé par le vendeur : proposez votre prix'; end if;
  if (select count(*) from public.delivery_jobs x where x.courier_id = v_uid and x.status in ('assigned','picked_up')) >= 3 then raise exception 'Vous avez déjà 3 missions en cours'; end if;
  update public.delivery_jobs set status = 'assigned', courier_id = v_uid, assigned_at = now() where id = j.id and status = 'open';
  if not found then raise exception 'La mission a été prise par un autre livreur'; end if;
  update public.delivery_job_offers set status = 'rejected', updated_at = now() where job_id = j.id and status = 'pending';
  insert into public.notifications(user_id, kind, title, body, ref) values (o.customer_id, 'offer', 'Livreur trouvé', 'Un livreur a accepté votre livraison immédiate au prix annoncé.', o.id);
end $$;
revoke all on function public.accept_fixed_price_job(uuid) from public, anon;
grant execute on function public.accept_fixed_price_job(uuid) to authenticated;

-- propose_delivery_price (V80 : position boutique facultative, GPS configurable)
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
  if v_lat is null or v_lng is null or v_updated is null or v_updated < now()-public._gps_max_age() then
    raise exception 'Position GPS absente ou trop ancienne';
  end if;
  select s.lat,s.lng into v_shop_lat,v_shop_lng
  from public.orders o join public.shops s on s.id=o.shop_id
  where o.id=v_job.order_id and o.delivery_mode='delivery'
    and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') and s.status='active';
  if not found then raise exception 'Commande non éligible à une offre de livraison'; end if;
  v_distance := case when v_shop_lat is null or v_shop_lng is null then 0 else public._km(v_shop_lat, v_shop_lng, v_lat, v_lng) end;
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
create or replace function public.select_delivery_price_offer(p_offer uuid) returns void
language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); f public.delivery_job_offers; j public.delivery_jobs; o public.orders; aid uuid; bal bigint; delta bigint; ref text;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  select * into f from public.delivery_job_offers where id=p_offer for update;
  if f.id is null then raise exception 'Offre introuvable'; end if;
  select * into j from public.delivery_jobs where id=f.job_id for update;
  if j.id is null or j.status<>'open' then raise exception 'La mission a déjà été attribuée ou fermée'; end if;
  select * into o from public.orders where id=j.order_id and customer_id=uid and delivery_mode='delivery' for update;
  if o.id is null then raise exception 'Seul le client de la commande peut choisir le prix'; end if;
  if o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') then raise exception 'Commande non éligible à la sélection d’un coursier'; end if;
  if f.status<>'pending' or f.expires_at<=now() then raise exception 'Cette offre a expiré'; end if;
  if f.currency<>o.currency or j.currency<>o.currency then raise exception 'La devise de l’offre ne correspond pas à la commande'; end if;
  if not exists(select 1 from public.courier_status cs where cs.user_id=f.courier_id and cs.available=true and cs.location_updated_at>now()-public._gps_max_age()) then
    raise exception 'Le coursier n’est plus disponible ou sa position est trop ancienne';
  end if;
  delta:=f.amount_minor-o.delivery_minor;
  if delta>0 then
    insert into public.wallet_accounts(user_id,currency) values(uid,o.currency) on conflict(user_id,currency) do nothing;
    select id into aid from public.wallet_accounts where user_id=uid and currency=o.currency for update;
    bal:=public._wallet_balance_minor(aid);
    if bal<delta then raise exception 'Solde % insuffisant pour le supplément : disponible %, requis % centimes',o.currency,bal,delta; end if;
    ref:='DELIVERY_OFFER:'||o.id::text;
    insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
    values(aid,uid,ref,'purchase','successful',delta,o.currency,'internal',jsonb_build_object('purpose','delivery_fee','order_id',o.id,'offer_id',f.id,'courier_id',f.courier_id));
  elsif delta<0 then
    insert into public.wallet_accounts(user_id,currency) values(uid,o.currency) on conflict(user_id,currency) do nothing;
    select id into aid from public.wallet_accounts where user_id=uid and currency=o.currency for update;
    ref:='DELIVERY_REFUND:'||o.id::text;
    insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
    values(aid,uid,ref,'refund','successful',abs(delta),o.currency,'internal',jsonb_build_object('purpose','delivery_fee_adjustment','order_id',o.id,'offer_id',f.id));
  end if;
  update public.orders set delivery_minor=f.amount_minor,total_minor=total_minor+delta where id=o.id;
  update public.delivery_jobs set status='assigned',courier_id=f.courier_id,assigned_at=now(),pay_minor=f.amount_minor,currency=f.currency where id=j.id and status='open';
  if not found then raise exception 'La mission a été attribuée simultanément à un autre coursier'; end if;
  update public.delivery_job_offers set status='selected',updated_at=now() where id=f.id;
  update public.delivery_job_offers set status='rejected',updated_at=now() where job_id=j.id and id<>f.id and status='pending';
end $$;
-- =====================================================================
-- 3. FICHE COMPLÈTE D'UNE COMMANDE (client, vendeur, livreur affecté, admin) : adresse, contacts, photos/vidéos, délais
--    Livreur NON encore affecté : aperçu sans contacts ni adresse exacte.
-- =====================================================================
create or replace function public.order_full_details(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); o public.orders; s public.shops; j public.delivery_jobs; v_full boolean; preview boolean := false; items jsonb;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  select * into o from public.orders where id = p_order;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  select * into s from public.shops where id = o.shop_id;
  select * into j from public.delivery_jobs where order_id = o.id;
  v_full := o.customer_id = uid or s.owner_id = uid or (j.courier_id is not null and j.courier_id = uid) or public.admin_unlocked();
  if not v_full then
    if j.id is not null and j.status = 'open' and public._is_approved_courier() and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') then preview := true;
    else raise exception 'Accès refusé'; end if;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'name', i.name, 'variant', i.variant_label, 'qty', i.qty, 'unit_minor', i.unit_minor, 'product_id', i.product_id,
      'image_url', (select m.url from public.product_media m where m.product_id = i.product_id and m.kind = 'image' order by m.position limit 1),
      'video_url', (select m.url from public.product_media m where m.product_id = i.product_id and m.kind = 'video' order by m.position limit 1)) order by i.name), '[]'::jsonb)
    into items from public.order_items i where i.order_id = o.id;
  return jsonb_build_object(
    'preview', preview,
    'id', o.id, 'status', o.status, 'mode', o.delivery_mode, 'currency', o.currency, 'total_minor', o.total_minor, 'items_minor', o.items_minor, 'delivery_minor', o.delivery_minor,
    'speed', o.delivery_speed, 'promised_minutes', o.promised_minutes, 'kind', o.delivery_kind, 'created_at', o.created_at,
    'landmark', case when preview then null else o.delivery_landmark end,
    'address', case when preview then null else o.delivery_address end,
    'lat', case when preview then null else o.delivery_lat end, 'lng', case when preview then null else o.delivery_lng end,
    'recipient', case when preview then null else o.delivery_recipient end,
    'customer_phone', case when preview then null else coalesce(o.delivery_phone, (select p.phone from public.profiles p where p.id = o.customer_id)) end,
    'customer_whatsapp', case when preview then null else coalesce(o.delivery_whatsapp, (select p.whatsapp from public.profiles p where p.id = o.customer_id)) end,
    'shop', jsonb_build_object('id', s.id, 'name', s.name, 'city', s.city, 'lat', s.lat, 'lng', s.lng, 'prep_minutes', s.prep_minutes),
    'items', items,
    'job', case when j.id is null then null else jsonb_build_object('id', j.id, 'status', j.status, 'pay_minor', j.pay_minor) end);
end $$;
revoke all on function public.order_full_details(uuid) from public, anon;
grant execute on function public.order_full_details(uuid) to authenticated;

-- =====================================================================
-- 4. MISSIONS DU LIVREUR avec identifiant de commande + résolution mission → commande
-- =====================================================================
create or replace function public.my_jobs_v80()
returns table(id uuid, order_id uuid, pickup_area text, dropoff_address text, pay_minor bigint, currency text, status text, delivery_kind text, delivery_speed text, promised_minutes integer)
language sql stable security definer set search_path = public as $$
  select j.id, j.order_id, j.pickup_area, j.dropoff_address, j.pay_minor, j.currency, j.status, o.delivery_kind, o.delivery_speed, o.promised_minutes
  from public.delivery_jobs j join public.orders o on o.id = j.order_id
  where j.courier_id = auth.uid() order by j.assigned_at desc nulls last limit 50 $$;
revoke all on function public.my_jobs_v80() from public, anon;
grant execute on function public.my_jobs_v80() to authenticated;

create or replace function public.job_order_id(p_job uuid) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v uuid;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select j.order_id into v from public.delivery_jobs j
   where j.id = p_job and (j.courier_id = auth.uid() or (j.status = 'open' and public._is_approved_courier()));
  return v;
end $$;
revoke all on function public.job_order_id(uuid) from public, anon;
grant execute on function public.job_order_id(uuid) to authenticated;
