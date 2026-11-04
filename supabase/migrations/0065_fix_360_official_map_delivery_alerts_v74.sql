-- HAITIKET V74 — correctifs fiche 360°, boutique officielle sur la carte, alertes de livraison.
-- À appliquer APRÈS 0064. Idempotent.

-- 1. CAUSE du bug de la fiche 360° : la fonction était déclarée STABLE mais écrit dans le journal d'audit
--    (erreur PostgreSQL « INSERT is not allowed in a non-volatile function »). On la rend VOLATILE.
alter function public.admin_user_360(uuid) volatile;

-- 2. Informations complémentaires de la fiche client
create or replace function public.admin_user_extra(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return jsonb_build_object(
    'addresses', coalesce((select jsonb_agg(x) from (select a.id,a.label,a.recipient,a.phone,a.commune,a.quarter,a.street,a.is_default from public.addresses a where a.user_id = p_user and a.active order by a.is_default desc, a.id limit 10) x), '[]'::jsonb),
    'tickets', coalesce((select jsonb_agg(x) from (select t.id,t.subject,t.status,t.created_at from public.support_tickets t where t.user_id = p_user order by t.created_at desc limit 10) x), '[]'::jsonb),
    'reports_against', (select count(*) from public.reports r where r.kind = 'user' and r.target_id = p_user),
    'reviews_given', (select count(*) from public.reviews r where r.reviewer_id = p_user),
    'favorites', (select count(*) from public.favorites f where f.user_id = p_user),
    'identity_status', (select v.status from public.identity_verifications v where v.user_id = p_user order by v.created_at desc limit 1),
    'referred_count', (select count(*) from public.profiles r where r.referred_by = p_user),
    'audit', coalesce((select jsonb_agg(x) from (select l.action,l.reason,l.created_at from public.admin_audit_logs l where l.resource_id = p_user order by l.created_at desc limit 15) x), '[]'::jsonb)
  );
end $$;
revoke all on function public.admin_user_extra(uuid) from public, anon;
grant execute on function public.admin_user_extra(uuid) to authenticated;

-- 3. Message individuel à un client
create or replace function public.admin_notify_user(p_user uuid, p_title text, p_body text, p_link text default null, p_coupon text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_coupon text := nullif(upper(trim(coalesce(p_coupon,''))),''); v_link text := nullif(trim(coalesce(p_link,'')),'');
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if char_length(btrim(coalesce(p_title,''))) < 2 or char_length(btrim(coalesce(p_body,''))) < 2 then raise exception 'Titre et message requis'; end if;
  if v_link is not null and v_link !~* '^https://' then raise exception 'Le lien doit commencer par https://'; end if;
  if v_coupon is not null and not exists(select 1 from public.coupons where code = v_coupon and active) then raise exception 'Coupon introuvable ou inactif'; end if;
  if not exists(select 1 from public.profiles where id = p_user) then raise exception 'Compte introuvable'; end if;
  insert into public.notifications(user_id, kind, title, body, link_url, coupon_code) values (p_user, 'broadcast', left(trim(p_title),100), left(trim(p_body),1200), v_link, v_coupon);
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'notify_user', 'user', p_user, left(trim(p_title),200));
end $$;
revoke all on function public.admin_notify_user(uuid,text,text,text,text) from public, anon;
grant execute on function public.admin_notify_user(uuid,text,text,text,text) to authenticated;

-- 4. BOUTIQUE OFFICIELLE SUR LA CARTE : tout administrateur déverrouillé peut en fixer la position
--    (avant : seul le propriétaire/créateur le pouvait, et rien ne l'exposait dans l'admin).
create or replace function public.set_shop_location(p_shop uuid, p_lat double precision, p_lng double precision) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'Position invalide'; end if;
  update public.shops set lat = round(p_lat::numeric, 3), lng = round(p_lng::numeric, 3)
  where id = p_shop and (owner_id = auth.uid() or (is_official and public.admin_unlocked()));
  if not found then raise exception 'Boutique introuvable'; end if;
end $$;
grant execute on function public.set_shop_location(uuid, double precision, double precision) to authenticated;

create or replace function public.admin_set_official_shop_location(p_lat double precision, p_lng double precision) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'Position invalide'; end if;
  update public.shops set lat = round(p_lat::numeric, 5), lng = round(p_lng::numeric, 5) where is_official;
  if not found then raise exception 'Créez d''abord la boutique officielle'; end if;
  insert into public.admin_audit_logs(actor, action, resource, reason) values (auth.uid(), 'set_official_shop_location', 'shop', p_lat::text || ',' || p_lng::text);
end $$;
revoke all on function public.admin_set_official_shop_location(double precision,double precision) from public, anon;
grant execute on function public.admin_set_official_shop_location(double precision,double precision) to authenticated;

-- 5. ALERTES DE LIVRAISON
-- 5a. Nouvelle mission : message correct quand le prix n'est pas encore fixé (le livreur propose son prix).
create or replace function public._trg_new_job() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications(user_id, kind, title, body, ref)
  select cs.user_id, 'job', 'Nouvelle mission de livraison',
         case when new.pay_minor > 0 then 'Rémunération : ' || (new.pay_minor / 100.0)::numeric(12,2) || ' ' || new.currency
              else 'Proposez votre prix et votre délai : ' || coalesce(new.pickup_area,'') end,
         new.id
  from public.courier_status cs
  where cs.available and exists (select 1 from public.courier_applications a where a.user_id = cs.user_id and a.status = 'approved');
  return new;
end $$;

-- 5b. Le client est averti dès qu'un livreur propose un prix.
create or replace function public._trg_new_offer() returns trigger language plpgsql security definer set search_path = public as $$
declare v_customer uuid; v_order uuid;
begin
  select o.customer_id, o.id into v_customer, v_order from public.delivery_jobs j join public.orders o on o.id = j.order_id where j.id = new.job_id;
  if v_customer is not null then
    insert into public.notifications(user_id, kind, title, body, ref)
    values (v_customer, 'offer', 'Un livreur propose son prix',
            (new.amount_minor / 100.0)::numeric(12,2) || ' ' || new.currency || ' · environ ' || new.eta_minutes || ' min. Ouvrez le suivi pour choisir.', v_order);
  end if;
  return new;
end $$;
drop trigger if exists notify_new_offer on public.delivery_job_offers;
create trigger notify_new_offer after insert on public.delivery_job_offers for each row execute function public._trg_new_offer();

-- 5c. Le livreur est averti quand son offre est retenue.
create or replace function public._trg_offer_selected() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'selected' and old.status is distinct from 'selected' then
    insert into public.notifications(user_id, kind, title, body, ref)
    values (new.courier_id, 'job', 'Offre acceptée', 'Le client a choisi votre offre. Rendez-vous à la boutique pour récupérer le colis.', new.job_id);
  end if;
  return new;
end $$;
drop trigger if exists notify_offer_selected on public.delivery_job_offers;
create trigger notify_offer_selected after update on public.delivery_job_offers for each row execute function public._trg_offer_selected();
