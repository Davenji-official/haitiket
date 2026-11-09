-- HAITIKET V81 — COMMANDE IMMÉDIATE / STANDARD (retrait ET livraison), au niveau des produits et des boutiques.
-- Cahier des charges §13 : objectif indicatif immédiat 45 min sans garantie ; estimation selon distance, préparation et disponibilité réelle ;
-- retards jusqu'à 2 ou 4 h sans inventer la progression ; absence de livreur gérée. À appliquer APRÈS 0071. Idempotent.

-- 1. Réglages : acceptation de l'immédiat = choix explicite du vendeur (désactivé par défaut)
alter table public.shops add column if not exists immediate_prep_minutes integer not null default 20;
alter table public.shops drop constraint if exists shops_immediate_prep_check;
alter table public.shops add constraint shops_immediate_prep_check check (immediate_prep_minutes between 5 and 240);
alter table public.delivery_jobs add column if not exists no_courier_notified_at timestamptz;

insert into public.platform_settings(key, value) values
  ('late_immediate_hours','4'), ('delivery_no_courier_minutes','15'), ('delivery_urban_speed_kmh','20'), ('delivery_immediate_sla_minutes','45')
on conflict (key) do nothing;

-- Remise à zéro UNE SEULE FOIS : l'immédiat n'était pas encore exposé aux vendeurs (aucun vendeur ne l'avait choisi).
do $$
begin
  if not exists (select 1 from public.platform_settings where key = 'migration_0072_immediate_optin') then
    alter table public.products alter column immediate_ok set default false;
    alter table public.shops alter column immediate_delivery_enabled set default false;
    update public.products set immediate_ok = false;
    update public.shops set immediate_delivery_enabled = false;
    insert into public.platform_settings(key, value) values ('migration_0072_immediate_optin', 'done');
  end if;
end $$;

-- 2. Estimation du délai : préparation + trajet (distance) + attente de livreur (disponibilité réelle)
create or replace function public._estimate_minutes(p_shop uuid, p_mode text, p_speed text, p_lat double precision, p_lng double precision, p_prep integer)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.shops; v_speed numeric := 20; v_prep integer; v_travel integer := 0; v_wait integer := 0; v_couriers integer := 0; v_km double precision; v_total integer;
begin
  select * into s from public.shops where id = p_shop;
  select coalesce(nullif(value,'')::numeric, 20) into v_speed from public.platform_settings where key = 'delivery_urban_speed_kmh';
  if v_speed is null or v_speed < 5 then v_speed := 20; end if;
  v_prep := case when p_speed = 'immediate' then coalesce(s.immediate_prep_minutes, 20) else greatest(1, coalesce(p_prep, s.prep_minutes, 30)) end;
  if p_mode = 'delivery' then
    if s.lat is not null and s.lng is not null and p_lat is not null and p_lng is not null then
      v_km := public._km(s.lat, s.lng, p_lat, p_lng);
      v_travel := greatest(10, round(v_km / v_speed * 60)::int + 5);
    else
      v_travel := 15;
    end if;
    select count(*) into v_couriers from public.courier_status cs
      where cs.available and cs.location_updated_at > now() - public._gps_max_age()
        and exists (select 1 from public.courier_applications a where a.user_id = cs.user_id and a.status = 'approved')
        and (s.lat is null or s.lng is null or cs.lat is null or public._km(s.lat, s.lng, cs.lat, cs.lng) <= 25);
    if v_couriers = 0 then v_wait := 30; end if;
  end if;
  v_total := v_prep + v_travel + v_wait;
  v_total := case when p_speed = 'immediate' then least(240, ((greatest(10, v_total) + 4) / 5) * 5) else ((v_total + 4) / 5) * 5 end;
  return jsonb_build_object('minutes', v_total, 'prep', v_prep, 'travel', v_travel, 'wait', v_wait, 'couriers_available', v_couriers);
end $$;
revoke all on function public._estimate_minutes(uuid,text,text,double precision,double precision,integer) from public, anon, authenticated;

-- Options affichées AVANT la commande : l'immédiat est-il possible pour chaque boutique du panier, et quel délai estimé ?
create or replace function public.estimate_delivery_options(p_items jsonb, p_mode text, p_lat double precision default null, p_lng double precision default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r record; res jsonb := '[]'::jsonb; v_sla integer := 45; v_imm jsonb; v_std jsonb; v_blockers text[]; v_ok boolean;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select coalesce(nullif(value,'')::int, 45) into v_sla from public.platform_settings where key = 'delivery_immediate_sla_minutes';
  for r in
    select s.id as shop_id, s.name as shop_name, s.immediate_delivery_enabled as imm_on, s.status as shop_status,
           s.immediate_fee_htg_minor, s.immediate_fee_usd_minor,
           max(coalesce(p.prep_minutes, s.prep_minutes)) as prep_std,
           coalesce(array_agg(p.name) filter (where not p.immediate_ok), array[]::text[]) as not_immediate
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) it
    join public.products p on p.id = (it->>'product_id')::uuid
    join public.shops s on s.id = p.shop_id
    group by s.id
  loop
    v_blockers := array[]::text[];
    if r.shop_status <> 'active' then v_blockers := v_blockers || 'La boutique n''est pas active.'; end if;
    if not r.imm_on then v_blockers := v_blockers || 'Le vendeur ne propose pas la commande immédiate.'; end if;
    if coalesce(array_length(r.not_immediate, 1), 0) > 0 then v_blockers := v_blockers || ('Non disponible en immédiat : ' || array_to_string(r.not_immediate, ', ')); end if;
    v_ok := coalesce(array_length(v_blockers, 1), 0) = 0;
    v_imm := public._estimate_minutes(r.shop_id, p_mode, 'immediate', p_lat, p_lng, null);
    v_std := public._estimate_minutes(r.shop_id, p_mode, 'standard', p_lat, p_lng, r.prep_std);
    res := res || jsonb_build_array(jsonb_build_object(
      'shop_id', r.shop_id, 'shop_name', r.shop_name, 'immediate_available', v_ok, 'blockers', to_jsonb(v_blockers),
      'immediate_minutes', (v_imm->>'minutes')::int, 'standard_minutes', (v_std->>'minutes')::int,
      'couriers_available', (v_imm->>'couriers_available')::int, 'objective_minutes', v_sla,
      'immediate_fee_htg_minor', r.immediate_fee_htg_minor, 'immediate_fee_usd_minor', r.immediate_fee_usd_minor));
  end loop;
  return res;
end $$;
revoke all on function public.estimate_delivery_options(jsonb,text,double precision,double precision) from public, anon;
grant execute on function public.estimate_delivery_options(jsonb,text,double precision,double precision) to authenticated;

-- 3. Détails de commande : le type (immédiate/standard) vaut pour le RETRAIT comme pour la LIVRAISON
create or replace function public.set_order_delivery_details(
  p_order uuid, p_kind text, p_landmark text, p_recipient text, p_phone text, p_whatsapp text, p_speed text default 'standard')
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; s public.shops; v_phone text; v_wa text; v_fee bigint; v_est jsonb; v_prep_items integer; v_sla integer := 45;
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
  if p_speed not in ('immediate','standard') then raise exception 'Type de commande invalide'; end if;
  if p_speed = 'immediate' then
    if not s.immediate_delivery_enabled then raise exception 'Cette boutique ne propose pas la commande immédiate'; end if;
    if exists (select 1 from public.order_items i join public.products p on p.id = i.product_id where i.order_id = o.id and not p.immediate_ok) then
      raise exception 'Un article de la commande n''est pas disponible en immédiat';
    end if;
  end if;
  select coalesce(nullif(value,'')::int, 45) into v_sla from public.platform_settings where key = 'delivery_immediate_sla_minutes';
  select max(coalesce(p.prep_minutes, s.prep_minutes)) into v_prep_items from public.order_items i join public.products p on p.id = i.product_id where i.order_id = o.id;
  v_est := public._estimate_minutes(o.shop_id, o.delivery_mode, p_speed, o.delivery_lat, o.delivery_lng, v_prep_items);

  v_fee := case when p_speed = 'immediate' and o.delivery_mode = 'delivery' then (case when o.currency = 'USD' then s.immediate_fee_usd_minor else s.immediate_fee_htg_minor end) else null end;
  update public.orders set
    delivery_kind = case when o.delivery_mode = 'delivery' then p_kind else 'pickup' end,
    delivery_landmark = nullif(left(trim(coalesce(p_landmark,'')),300),''),
    delivery_recipient = nullif(left(trim(coalesce(p_recipient,'')),80),''),
    delivery_phone = v_phone, delivery_whatsapp = v_wa, delivery_speed = p_speed, promised_minutes = (v_est->>'minutes')::int
  where id = o.id;
  if v_fee is not null and v_fee > 0 then
    update public.orders set total_minor = total_minor - delivery_minor + v_fee, delivery_minor = v_fee where id = o.id;
  end if;
  update public.profiles set phone = coalesce(nullif(phone,''), v_phone), whatsapp = coalesce(nullif(whatsapp,''), v_wa) where id = auth.uid();
  return jsonb_build_object('delivery_minor', coalesce(v_fee, o.delivery_minor), 'fixed_fee', coalesce(v_fee > 0, false),
    'promised_minutes', (v_est->>'minutes')::int, 'speed', p_speed, 'objective_minutes', v_sla,
    'exceeds_objective', p_speed = 'immediate' and (v_est->>'minutes')::int > v_sla, 'couriers_available', (v_est->>'couriers_available')::int);
end $$;
revoke all on function public.set_order_delivery_details(uuid,text,text,text,text,text,text) from public, anon;
grant execute on function public.set_order_delivery_details(uuid,text,text,text,text,text,text) to authenticated;

-- 4. Échéance de retard selon le type : immédiat = 4 h max (estimation haute du cahier) ; standard = préparation annoncée + délai habituel
create or replace function public._orders_set_due_v72() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_imm_hours integer := 4;
begin
  if new.status = 'PAID' and old.status is distinct from 'PAID' and new.delivery_due_at is null then
    select coalesce(nullif(value,'')::int, 4) into v_imm_hours from public.platform_settings where key = 'late_immediate_hours';
    if new.delivery_speed = 'immediate' then
      new.delivery_due_at := now() + make_interval(hours => greatest(1, v_imm_hours));
    else
      new.delivery_due_at := now() + make_interval(mins => coalesce(new.promised_minutes, 0)) + make_interval(hours => public._due_hours_v72(new.delivery_mode));
    end if;
  end if;
  return new;
end $$;

-- 5. Le vendeur est alerté en priorité d'une commande IMMÉDIATE
create or replace function public._trg_order_paid_notify_seller() returns trigger language plpgsql security definer set search_path = public as $$
declare v_owner uuid; v_mins integer;
begin
  if new.status = 'PAID' and old.status is distinct from 'PAID' and new.delivery_speed = 'immediate' then
    select owner_id into v_owner from public.shops where id = new.shop_id;
    v_mins := coalesce(new.promised_minutes, 45);
    if v_owner is not null then
      insert into public.notifications(user_id, kind, title, body, ref)
      values (v_owner, 'order', '⚡ Commande IMMÉDIATE à préparer maintenant',
              'À remettre avant ' || to_char((now() at time zone 'America/Port-au-Prince') + make_interval(mins => v_mins), 'HH24:MI') || ' (estimation ~' || v_mins || ' min, indicatif).', new.id);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists orders_paid_notify_seller on public.orders;
create trigger orders_paid_notify_seller after update of status on public.orders for each row execute function public._trg_order_paid_notify_seller();

-- 6. Alerte livreurs : mission IMMÉDIATE signalée comme telle (reprend la version 0066, rayon + repli)
create or replace function public._trg_new_job() returns trigger language plpgsql security definer set search_path = public as $$
declare v_lat double precision; v_lng double precision; v_radius double precision; v_n integer; v_speed text; v_title text; v_body text;
begin
  select s.lat, s.lng, o.delivery_speed into v_lat, v_lng, v_speed from public.orders o join public.shops s on s.id = o.shop_id where o.id = new.order_id;
  select coalesce(nullif((select value from public.platform_settings where key = 'courier_alert_radius_km'),'')::double precision, 15) into v_radius;
  v_title := case when v_speed = 'immediate' then '⚡ Mission IMMÉDIATE de livraison' else 'Nouvelle mission de livraison' end;
  v_body := case when new.pay_minor > 0 then 'Rémunération : ' || (new.pay_minor / 100.0)::numeric(12,2) || ' ' || new.currency
                 else 'Proposez votre prix et votre délai : ' || coalesce(new.pickup_area,'') end;
  insert into public.notifications(user_id, kind, title, body, ref)
  select cs.user_id, 'job', v_title, v_body, new.id from public.courier_status cs
  where cs.available and exists (select 1 from public.courier_applications a where a.user_id = cs.user_id and a.status = 'approved')
    and (v_lat is null or cs.lat is null or cs.location_updated_at < now() - interval '30 minutes' or public._km(v_lat, v_lng, cs.lat, cs.lng) <= v_radius);
  get diagnostics v_n = row_count;
  if v_n = 0 then
    insert into public.notifications(user_id, kind, title, body, ref)
    select cs.user_id, 'job', v_title, v_body, new.id from public.courier_status cs
    where cs.available and exists (select 1 from public.courier_applications a where a.user_id = cs.user_id and a.status = 'approved');
  end if;
  return new;
end $$;

-- 7. Absence de livreur : le client est prévenu et peut annuler (remboursement selon les règles) ; déclenché par l'activité des utilisateurs
create or replace function public.process_unassigned_jobs() returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0; v_min integer := 15;
begin
  select coalesce(nullif(value,'')::int, 15) into v_min from public.platform_settings where key = 'delivery_no_courier_minutes';
  for r in
    select j.id as job_id, o.id as order_id, o.customer_id, o.delivery_speed
    from public.delivery_jobs j join public.orders o on o.id = j.order_id
    where j.status = 'open' and j.no_courier_notified_at is null
      and j.created_at < now() - make_interval(mins => case when o.delivery_speed = 'immediate' then greatest(5, v_min / 2) else v_min * 2 end)
      and not exists (select 1 from public.delivery_job_offers f where f.job_id = j.id and f.status = 'pending')
    limit 50
  loop
    insert into public.notifications(user_id, kind, title, body, ref)
    values (r.customer_id, 'order', 'Aucun livreur pour l''instant',
            'Votre commande attend encore un livreur. Vous pouvez patienter, ou l''annuler depuis son suivi pour être remboursé selon les règles.', r.order_id);
    update public.delivery_jobs set no_courier_notified_at = now() where id = r.job_id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.process_unassigned_jobs() from public, anon, authenticated;

create or replace function public.touch_presence() returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set last_seen_at = now()
  where id = auth.uid() and (last_seen_at is null or last_seen_at < now() - interval '45 seconds');
  perform public.restore_expired_support_bans();
  if random() < 0.25 then perform public.process_unassigned_jobs(); end if;
end $$;
revoke all on function public.touch_presence() from public, anon;
grant execute on function public.touch_presence() to authenticated;

-- 8. Missions ouvertes : immédiat en premier
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
         case when s.lat is null or s.lng is null then null else round((6371.0 * 2 * asin(sqrt(least(1.0, greatest(0.0,
           power(sin(radians(s.lat - v_lat) / 2), 2) + cos(radians(v_lat)) * cos(radians(s.lat)) * power(sin(radians(s.lng - v_lng) / 2), 2)))))))::numeric, 1) end,
         s.name
  from public.delivery_jobs j
  join public.orders o on o.id = j.order_id
  join public.shops s on s.id = o.shop_id
  where j.status = 'open' and o.delivery_mode = 'delivery'
    and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') and s.status = 'active'
    and (s.lat is null or s.lng is null or 6371.0 * 2 * asin(sqrt(least(1.0, greatest(0.0,
         power(sin(radians(s.lat - v_lat) / 2), 2) + cos(radians(v_lat)) * cos(radians(s.lat)) * power(sin(radians(s.lng - v_lng) / 2), 2))))) <= 25.0)
  order by (o.delivery_speed = 'immediate') desc, j.created_at desc limit 50;
end $$;
revoke all on function public.list_open_jobs_v80() from public, anon;
grant execute on function public.list_open_jobs_v80() to authenticated;

-- 9. Réglages vendeur v81 : acceptation de l'immédiat (retrait + livraison), préparation immédiate, prix d'immédiat
create or replace function public.seller_set_delivery_settings_v81(p_shop uuid, p_prep_minutes integer, p_immediate boolean, p_immediate_prep integer, p_fee_htg_minor bigint, p_fee_usd_minor bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if p_prep_minutes is null or p_prep_minutes < 1 or p_prep_minutes > 14400 then raise exception 'Délai de préparation standard invalide (1 minute à 10 jours)'; end if;
  if p_immediate_prep is null or p_immediate_prep < 5 or p_immediate_prep > 240 then raise exception 'Préparation immédiate invalide (5 à 240 minutes)'; end if;
  if (p_fee_htg_minor is not null and p_fee_htg_minor < 0) or (p_fee_usd_minor is not null and p_fee_usd_minor < 0) then raise exception 'Prix invalide'; end if;
  update public.shops set prep_minutes = least(p_prep_minutes, 1440), immediate_delivery_enabled = coalesce(p_immediate, false), immediate_prep_minutes = p_immediate_prep,
    immediate_fee_htg_minor = nullif(p_fee_htg_minor, 0), immediate_fee_usd_minor = nullif(p_fee_usd_minor, 0)
  where id = p_shop and owner_id = auth.uid();
  if not found then raise exception 'Boutique introuvable ou accès refusé'; end if;
end $$;
revoke all on function public.seller_set_delivery_settings_v81(uuid,integer,boolean,integer,bigint,bigint) from public, anon;
grant execute on function public.seller_set_delivery_settings_v81(uuid,integer,boolean,integer,bigint,bigint) to authenticated;

-- 10. Produit : commande immédiate possible + délai de préparation standard (le vendeur propriétaire uniquement)
create or replace function public.seller_set_product_order_options(p_product uuid, p_immediate_ok boolean, p_prep_minutes integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if p_prep_minutes is not null and (p_prep_minutes < 1 or p_prep_minutes > 14400) then raise exception 'Délai invalide (1 minute à 10 jours)'; end if;
  update public.products p set immediate_ok = coalesce(p_immediate_ok, false), prep_minutes = p_prep_minutes
  where p.id = p_product and exists (select 1 from public.shops s where s.id = p.shop_id and s.owner_id = auth.uid());
  if not found then raise exception 'Produit introuvable ou accès refusé'; end if;
end $$;
revoke all on function public.seller_set_product_order_options(uuid,boolean,integer) from public, anon;
grant execute on function public.seller_set_product_order_options(uuid,boolean,integer) to authenticated;
