-- HAITIKET V82 — réaffectation du livreur, refus de mission, codes PIN/QR à durée limitée, conversion HTG<->USD entre portefeuilles,
-- taux USD propre à chaque boutique. À appliquer APRÈS 0072. Idempotent.

create or replace function public._km(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 6371 * 2 * asin(least(1, sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))) $$;

-- =====================================================================
-- 1. CODES PIN / QR : aléatoire fort + durée de validité (cahier §16)
-- =====================================================================
create or replace function public._gen_pin() returns text language sql as $$
  select lpad((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint % 1000000)::text, 6, '0') $$;

insert into public.platform_settings(key, value) values ('pin_validity_hours','48') on conflict (key) do nothing;
alter table public.order_pins add column if not exists issued_at timestamptz not null default now();
alter table public.delivery_jobs add column if not exists pickup_pin_issued_at timestamptz not null default now();

create or replace function public._pin_validity() returns interval language sql stable security definer set search_path = public as $$
  select make_interval(hours => greatest(1, least(720, coalesce((select nullif(value,'')::int from public.platform_settings where key = 'pin_validity_hours'), 48)))) $$;
revoke all on function public._pin_validity() from public, anon, authenticated;

-- Renouvelle les codes expirés des commandes en cours : l'ancien code cesse de fonctionner, le nouveau est visible dans l'application.
create or replace function public.rotate_expired_pins() returns integer
language plpgsql security definer set search_path = public as $$
declare n integer := 0; r record;
begin
  for r in
    update public.order_pins p set pin = public._gen_pin(), issued_at = now(), failed = 0
    from public.orders o
    where o.id = p.order_id and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT') and p.issued_at < now() - public._pin_validity()
    returning o.id as order_id, o.customer_id, o.status
  loop
    n := n + 1;
    if r.status in ('READY_FOR_PICKUP','IN_TRANSIT') then
      insert into public.notifications(user_id, kind, title, body, ref)
      values (r.customer_id, 'order', 'Code de remise renouvelé', 'Pour votre sécurité, votre code a été renouvelé. Ouvrez Mes commandes > Code pour voir le nouveau.', r.order_id);
    end if;
  end loop;
  update public.delivery_jobs set pickup_pin = public._gen_pin(), pickup_pin_issued_at = now(), failed = 0
  where status in ('open','assigned') and pickup_pin_issued_at < now() - public._pin_validity();
  return n;
end $$;
revoke all on function public.rotate_expired_pins() from public, anon, authenticated;

create or replace function public.get_order_pin(p_order uuid) returns text
language plpgsql security definer set search_path = public as $$
declare cust uuid; own uuid; r text; st text;
begin
  select o.customer_id, s.owner_id, o.status into cust, own, st from public.orders o join public.shops s on s.id = o.shop_id where o.id = p_order;
  if st is null or st in ('PENDING_PAYMENT','CANCELLED','REFUNDED') then return null; end if;
  if auth.uid() = cust then
    update public.order_pins set pin = public._gen_pin(), issued_at = now(), failed = 0 where order_id = p_order and issued_at < now() - public._pin_validity();
    select pin into r from public.order_pins where order_id = p_order;
  elsif auth.uid() = own then
    update public.delivery_jobs set pickup_pin = public._gen_pin(), pickup_pin_issued_at = now(), failed = 0 where order_id = p_order and status in ('open','assigned') and pickup_pin_issued_at < now() - public._pin_validity();
    select pickup_pin into r from public.delivery_jobs where order_id = p_order;
  end if;
  return r;
end $$;

-- =====================================================================
-- 2. LIVREUR : refuser une mission, prix de livraison toujours proposé par les livreurs
-- =====================================================================
create table if not exists public.delivery_job_declines (
  job_id uuid not null references public.delivery_jobs(id) on delete cascade,
  courier_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (job_id, courier_id)
);
alter table public.delivery_job_declines enable row level security;
revoke all on public.delivery_job_declines from anon, authenticated;

create or replace function public.decline_job(p_job uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if not public._is_approved_courier() then raise exception 'Candidature non approuvée'; end if;
  insert into public.delivery_job_declines(job_id, courier_id) values (p_job, auth.uid()) on conflict do nothing;
  update public.delivery_job_offers set status = 'withdrawn', updated_at = now() where job_id = p_job and courier_id = auth.uid() and status = 'pending';
end $$;
revoke all on function public.decline_job(uuid) from public, anon;
grant execute on function public.decline_job(uuid) to authenticated;

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
    and not exists (select 1 from public.delivery_job_declines d where d.job_id = j.id and d.courier_id = v_uid)
  order by (o.delivery_speed = 'immediate') desc, j.created_at desc limit 50;
end $$;
revoke all on function public.list_open_jobs_v80() from public, anon;
grant execute on function public.list_open_jobs_v80() to authenticated;

-- Le vendeur ne fixe JAMAIS le prix de livraison : l'acceptation à prix imposé est désactivée.
create or replace function public.accept_fixed_price_job(p_job uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Le prix de livraison est proposé par les livreurs et choisi par le client.';
end $$;

-- Sélection d'une offre : références comptables UNIQUES par offre (permet une réaffectation puis une nouvelle sélection)
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
    ref:='DELIVERY_OFFER:'||o.id::text||':'||f.id::text;
    insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
    values(aid,uid,ref,'purchase','successful',delta,o.currency,'internal',jsonb_build_object('purpose','delivery_fee','order_id',o.id,'offer_id',f.id,'courier_id',f.courier_id));
  elsif delta<0 then
    insert into public.wallet_accounts(user_id,currency) values(uid,o.currency) on conflict(user_id,currency) do nothing;
    select id into aid from public.wallet_accounts where user_id=uid and currency=o.currency for update;
    ref:='DELIVERY_REFUND:'||o.id::text||':'||f.id::text;
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
-- 3. RÉAFFECTATION : livreur indisponible, refus après acceptation, demande du client, décision admin
-- =====================================================================
insert into public.platform_settings(key, value) values ('reassign_after_minutes','20') on conflict (key) do nothing;

create or replace function public._reopen_job(p_job uuid, p_reason text) returns uuid
language plpgsql security definer set search_path = public as $$
declare j public.delivery_jobs; o public.orders; aid uuid; v_paid bigint; v_old uuid;
begin
  select * into j from public.delivery_jobs where id = p_job for update;
  if j.id is null then raise exception 'Mission introuvable'; end if;
  if j.status <> 'assigned' then raise exception 'La mission ne peut être rouverte qu''avant la collecte du colis'; end if;
  select * into o from public.orders where id = j.order_id for update;
  if o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') then raise exception 'Commande non éligible à la réaffectation'; end if;
  v_old := j.courier_id; v_paid := o.delivery_minor;
  if v_paid > 0 then
    insert into public.wallet_accounts(user_id, currency) values (o.customer_id, o.currency) on conflict do nothing;
    select id into aid from public.wallet_accounts where user_id = o.customer_id and currency = o.currency for update;
    insert into public.wallet_transactions(account_id, user_id, reference, kind, status, amount_minor, currency, provider, metadata)
    values (aid, o.customer_id, 'DELIVERY_REASSIGN:' || o.id::text || ':' || j.id::text || ':' || floor(extract(epoch from clock_timestamp()))::bigint::text,
            'refund', 'successful', v_paid, o.currency, 'internal',
            jsonb_build_object('purpose','delivery_reassignment','order_id',o.id,'job_id',j.id,'courier_id',v_old,'reason',left(coalesce(p_reason,''),200)));
    update public.orders set total_minor = total_minor - v_paid, delivery_minor = 0 where id = o.id;
  end if;
  update public.delivery_job_offers set status = 'withdrawn', updated_at = now() where job_id = j.id and status in ('selected','pending');
  update public.delivery_jobs set status = 'open', courier_id = null, assigned_at = null, pay_minor = 0, no_courier_notified_at = null where id = j.id;
  insert into public.notifications(user_id, kind, title, body, ref)
  values (o.customer_id, 'order', 'Nouveau livreur à choisir', 'Votre livreur n''est plus disponible. Le montant de sa livraison vous a été remboursé : choisissez une nouvelle offre depuis le suivi.', o.id);
  if v_old is not null then
    insert into public.notifications(user_id, kind, title, body, ref) values (v_old, 'job', 'Mission retirée', 'Cette mission vous a été retirée.', j.id);
  end if;
  return o.id;
end $$;
revoke all on function public._reopen_job(uuid,text) from public, anon, authenticated;

create or replace function public.courier_release_job(p_job uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from public.delivery_jobs where id = p_job and courier_id = auth.uid()) then raise exception 'Mission introuvable'; end if;
  perform public._reopen_job(p_job, coalesce(nullif(trim(p_reason),''), 'libérée par le livreur'));
  insert into public.delivery_job_declines(job_id, courier_id) values (p_job, auth.uid()) on conflict do nothing;
end $$;
revoke all on function public.courier_release_job(uuid,text) from public, anon;
grant execute on function public.courier_release_job(uuid,text) to authenticated;

create or replace function public.customer_request_reassignment(p_order uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; j public.delivery_jobs; cs public.courier_status; v_min integer := 20; v_stale boolean;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into o from public.orders where id = p_order;
  if o.id is null or o.customer_id <> auth.uid() then raise exception 'Commande introuvable'; end if;
  select * into j from public.delivery_jobs where order_id = o.id;
  if j.id is null or j.status <> 'assigned' then raise exception 'Aucun livreur à remplacer (le colis est peut-être déjà en route)'; end if;
  select coalesce(nullif(value,'')::int, 20) into v_min from public.platform_settings where key = 'reassign_after_minutes';
  select * into cs from public.courier_status where user_id = j.courier_id;
  v_stale := cs.user_id is null or not coalesce(cs.available, false) or cs.location_updated_at is null or cs.location_updated_at < now() - interval '15 minutes';
  if not v_stale and j.assigned_at > now() - make_interval(mins => v_min) then
    raise exception 'Le livreur a été choisi il y a moins de % minutes et reste joignable : contactez-le d''abord (appel / WhatsApp).', v_min;
  end if;
  perform public._reopen_job(j.id, coalesce(nullif(trim(p_reason),''), 'demande du client'));
end $$;
revoke all on function public.customer_request_reassignment(uuid,text) from public, anon;
grant execute on function public.customer_request_reassignment(uuid,text) to authenticated;

create or replace function public.admin_reopen_job(p_order uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare v_job uuid;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if char_length(btrim(coalesce(p_reason,''))) < 5 then raise exception 'Motif requis (5 caractères minimum)'; end if;
  select id into v_job from public.delivery_jobs where order_id = p_order;
  if v_job is null then raise exception 'Aucune mission pour cette commande'; end if;
  perform public._reopen_job(v_job, 'admin : ' || p_reason);
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'reopen_delivery_job', 'order', p_order, left(p_reason,200));
end $$;
revoke all on function public.admin_reopen_job(uuid,text) from public, anon;
grant execute on function public.admin_reopen_job(uuid,text) to authenticated;

-- =====================================================================
-- 4. CONVERSION HTG <-> USD ENTRE SES PORTEFEUILLES (taux fixé par l'administration)
-- =====================================================================
insert into public.platform_settings(key, value) values ('wallet_conversion_fee_bps','0') on conflict (key) do nothing;

create or replace function public._convert_rate() returns numeric language plpgsql stable security definer set search_path = public as $$
declare r numeric;
begin
  select nullif(value,'')::numeric into r from public.platform_settings where key = 'usd_htg_convert_rate';
  if r is null then select nullif(value,'')::numeric into r from public.platform_settings where key = 'usd_htg_rate'; end if;
  if r is null or r <= 0 then return null; end if;
  return r;
exception when others then return null;
end $$;
revoke all on function public._convert_rate() from public, anon, authenticated;

create or replace function public.wallet_conversion_quote(p_from text, p_amount_minor bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r numeric; fee_bps integer := 0; gross bigint; fee bigint; v_to text;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if p_from not in ('HTG','USD') then raise exception 'Devise invalide'; end if;
  if p_amount_minor is null or p_amount_minor <= 0 then raise exception 'Montant invalide'; end if;
  r := public._convert_rate();
  if r is null then raise exception 'Taux de conversion non configuré par l''administration'; end if;
  select coalesce(nullif(value,'')::int, 0) into fee_bps from public.platform_settings where key = 'wallet_conversion_fee_bps';
  v_to := case when p_from = 'HTG' then 'USD' else 'HTG' end;
  gross := case when p_from = 'HTG' then floor(p_amount_minor / r)::bigint else floor(p_amount_minor * r)::bigint end;
  fee := floor(gross * coalesce(fee_bps,0) / 10000.0)::bigint;
  return jsonb_build_object('rate', r, 'from', p_from, 'to', v_to, 'from_minor', p_amount_minor, 'gross_minor', gross, 'fee_minor', fee, 'to_minor', gross - fee, 'fee_bps', coalesce(fee_bps,0));
end $$;
revoke all on function public.wallet_conversion_quote(text,bigint) from public, anon;
grant execute on function public.wallet_conversion_quote(text,bigint) to authenticated;

create or replace function public.wallet_convert(p_from text, p_amount_minor bigint, p_request uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); q jsonb; a_from uuid; a_to uuid; v_to text; bal bigint; ref_out text; ref_in text; v_min bigint;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  if p_request is null then raise exception 'Identifiant de demande manquant'; end if;
  if p_from not in ('HTG','USD') then raise exception 'Devise invalide'; end if;
  v_min := case when p_from = 'HTG' then 2000 else 100 end;
  if p_amount_minor is null or p_amount_minor < v_min then raise exception 'Montant minimum : % %', (v_min / 100), p_from; end if;
  ref_out := 'CONV:' || p_request::text || ':OUT';
  ref_in := 'CONV:' || p_request::text || ':IN';
  if exists (select 1 from public.wallet_transactions where reference = ref_out and user_id = uid) then
    return jsonb_build_object('status', 'already_done');
  end if;
  q := public.wallet_conversion_quote(p_from, p_amount_minor);
  if (q->>'to_minor')::bigint < 1 then raise exception 'Montant trop faible pour être converti'; end if;
  v_to := q->>'to';
  insert into public.wallet_accounts(user_id, currency) values (uid, 'HTG') on conflict do nothing;
  insert into public.wallet_accounts(user_id, currency) values (uid, 'USD') on conflict do nothing;
  select id into a_from from public.wallet_accounts where user_id = uid and currency = 'HTG' for update;
  select id into a_to from public.wallet_accounts where user_id = uid and currency = 'USD' for update;
  if p_from = 'USD' then
    select id into a_from from public.wallet_accounts where user_id = uid and currency = 'USD';
    select id into a_to from public.wallet_accounts where user_id = uid and currency = 'HTG';
  end if;
  bal := public._wallet_balance_minor(a_from);
  if bal < p_amount_minor then raise exception 'Solde % insuffisant', p_from; end if;
  insert into public.wallet_transactions(account_id, user_id, reference, kind, status, amount_minor, currency, provider, metadata)
  values (a_from, uid, ref_out, 'purchase', 'successful', p_amount_minor, p_from, 'internal',
          jsonb_build_object('purpose','currency_conversion','direction','out','to_currency',v_to,'rate',q->'rate','to_minor',(q->>'to_minor')::bigint,'fee_minor',(q->>'fee_minor')::bigint));
  insert into public.wallet_transactions(account_id, user_id, reference, kind, status, amount_minor, currency, provider, metadata)
  values (a_to, uid, ref_in, 'adjustment', 'successful', (q->>'to_minor')::bigint, v_to, 'internal',
          jsonb_build_object('purpose','currency_conversion','direction','in','from_currency',p_from,'from_minor',p_amount_minor,'rate',q->'rate'));
  insert into public.notifications(user_id, kind, title, body, ref)
  values (uid, 'wallet', 'Conversion effectuée', (p_amount_minor / 100.0)::numeric(14,2) || ' ' || p_from || ' → ' || ((q->>'to_minor')::bigint / 100.0)::numeric(14,2) || ' ' || v_to || ' (taux ' || (q->>'rate') || ')', null);
  return q || jsonb_build_object('status', 'done');
end $$;
revoke all on function public.wallet_convert(text,bigint,uuid) from public, anon;
grant execute on function public.wallet_convert(text,bigint,uuid) to authenticated;

-- =====================================================================
-- 5. TAUX USD PROPRE À LA BOUTIQUE (produits en USD payables en gourdes)
-- =====================================================================
alter table public.shops add column if not exists usd_htg_rate numeric;
alter table public.shops drop constraint if exists shops_usd_htg_rate_check;
alter table public.shops add constraint shops_usd_htg_rate_check check (usd_htg_rate is null or (usd_htg_rate > 0 and usd_htg_rate < 100000));
insert into public.platform_settings(key, value) values ('seller_rate_max_deviation_pct','25') on conflict (key) do nothing;

create table if not exists public.order_currency_conversions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  from_currency text not null, to_currency text not null, rate numeric not null, rate_source text not null,
  amounts jsonb not null, created_by uuid, created_at timestamptz not null default now()
);
alter table public.order_currency_conversions enable row level security;
revoke all on public.order_currency_conversions from anon, authenticated;

create or replace function public.seller_set_usd_rate(p_shop uuid, p_rate numeric) returns void
language plpgsql security definer set search_path = public as $$
declare v_base numeric; v_dev numeric := 25;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if p_rate is not null then
    v_base := public._convert_rate();
    select coalesce(nullif(value,'')::numeric, 25) into v_dev from public.platform_settings where key = 'seller_rate_max_deviation_pct';
    if p_rate <= 0 then raise exception 'Taux invalide'; end if;
    if v_base is not null and abs(p_rate - v_base) / v_base * 100 > v_dev then
      raise exception 'Taux trop éloigné du taux de la plateforme (%) : maximum ±% %%.', round(v_base, 2), v_dev;
    end if;
  end if;
  update public.shops set usd_htg_rate = p_rate where id = p_shop and owner_id = auth.uid();
  if not found then raise exception 'Boutique introuvable ou accès refusé'; end if;
end $$;
revoke all on function public.seller_set_usd_rate(uuid,numeric) from public, anon;
grant execute on function public.seller_set_usd_rate(uuid,numeric) to authenticated;

-- Taux applicable pour payer en gourdes une commande en USD de cette boutique
create or replace function public.shop_usd_rate(p_shop uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_own numeric; v_base numeric;
begin
  select usd_htg_rate into v_own from public.shops where id = p_shop;
  v_base := public._convert_rate();
  return jsonb_build_object('rate', coalesce(v_own, v_base), 'own', v_own is not null, 'platform_rate', v_base);
end $$;
revoke all on function public.shop_usd_rate(uuid) from public, anon;
grant execute on function public.shop_usd_rate(uuid) to authenticated;

-- Le client paie en gourdes une commande en USD AVANT paiement : tous les montants sont convertis au taux de la boutique, de façon tracée.
create or replace function public.convert_order_currency(p_order uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.orders; s public.shops; r numeric; v_src text; g_seller bigint; g_plat bigint; a jsonb;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into o from public.orders where id = p_order for update;
  if o.id is null or o.customer_id <> auth.uid() then raise exception 'Commande introuvable ou accès refusé'; end if;
  if o.status <> 'PENDING_PAYMENT' then raise exception 'La devise ne peut être changée qu''avant le paiement'; end if;
  if o.currency <> 'USD' then return jsonb_build_object('status','already_htg'); end if;
  select * into s from public.shops where id = o.shop_id;
  r := coalesce(s.usd_htg_rate, public._convert_rate());
  v_src := case when s.usd_htg_rate is not null then 'shop' else 'platform' end;
  if r is null or r <= 0 then raise exception 'Aucun taux disponible pour cette boutique'; end if;
  g_seller := o.items_minor - o.commission_minor - o.seller_net_minor;
  g_plat := case when o.platform_net_minor is null then 0 else o.commission_minor - o.platform_net_minor end;
  a := jsonb_build_object('items', o.items_minor, 'discount', o.discount_minor, 'delivery', o.delivery_minor, 'commission', o.commission_minor, 'total', o.total_minor);
  update public.order_items set unit_minor = round(unit_minor * r)::bigint where order_id = o.id;
  update public.orders set
    currency = 'HTG',
    items_minor = round(items_minor * r)::bigint,
    discount_minor = round(discount_minor * r)::bigint,
    delivery_minor = round(delivery_minor * r)::bigint,
    commission_minor = round(commission_minor * r)::bigint,
    seller_net_minor = round(items_minor * r)::bigint - round(commission_minor * r)::bigint - round(g_seller * r)::bigint,
    platform_net_minor = case when platform_net_minor is null then null else round(commission_minor * r)::bigint - round(g_plat * r)::bigint end,
    total_minor = round(items_minor * r)::bigint - round(discount_minor * r)::bigint + round(delivery_minor * r)::bigint,
    immediate_fee_minor = round(immediate_fee_minor * r)::bigint
  where id = o.id;
  update public.delivery_jobs set currency = 'HTG', pay_minor = round(pay_minor * r)::bigint where order_id = o.id;
  insert into public.order_currency_conversions(order_id, from_currency, to_currency, rate, rate_source, amounts, created_by)
  values (o.id, 'USD', 'HTG', r, v_src, a, auth.uid());
  return jsonb_build_object('status', 'converted', 'rate', r, 'source', v_src, 'total_minor', (select total_minor from public.orders where id = o.id));
end $$;
revoke all on function public.convert_order_currency(uuid) from public, anon;
grant execute on function public.convert_order_currency(uuid) to authenticated;

-- =====================================================================
-- 6. Rotation des codes expirés déclenchée par l'activité des utilisateurs
-- =====================================================================
create or replace function public.touch_presence() returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set last_seen_at = now()
  where id = auth.uid() and (last_seen_at is null or last_seen_at < now() - interval '45 seconds');
  perform public.restore_expired_support_bans();
  if random() < 0.25 then
    perform public.process_unassigned_jobs();
    perform public.rotate_expired_pins();
  end if;
end $$;
revoke all on function public.touch_presence() from public, anon;
grant execute on function public.touch_presence() to authenticated;
