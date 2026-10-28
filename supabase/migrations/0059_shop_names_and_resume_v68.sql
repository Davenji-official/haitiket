-- HAITIKET 0059 : noms de boutique libérés après fermeture définitive, vérification de disponibilité,
-- reprise d'une suspension volontaire. Ré-exécutable sans risque.
--
-- Avant : l'unicité du nom couvrait TOUTES les boutiques, y compris celles fermées définitivement ;
-- un nom restait donc réservé pour toujours (et l'erreur « shops_name_normalized_unique_v53 » apparaissait).
-- Maintenant : seules les boutiques NON fermées réservent leur nom. Une boutique « suspendue » ou « en cours de
-- suppression » garde son nom ; il redevient libre uniquement quand l'administration finalise la fermeture.

begin;

drop index if exists public.shops_name_normalized_unique_v53;
create unique index if not exists shops_name_normalized_unique_v53
  on public.shops (lower(regexp_replace(btrim(name), '\s+', ' ', 'g')))
  where status <> 'closed';

-- Disponibilité d'un nom (utilisable avant de remplir tout le formulaire).
create or replace function public.shop_name_available_v68(p_name text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if char_length(v_name) < 2 or char_length(v_name) > 80 then
    return jsonb_build_object('available', false, 'reason', 'length', 'name', v_name);
  end if;
  return jsonb_build_object(
    'available', not exists (select 1 from public.shops s where s.status <> 'closed' and lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')) = lower(v_name)),
    'reason', 'taken',
    'name', v_name);
end;
$$;
revoke all on function public.shop_name_available_v68(text) from public, anon;
grant execute on function public.shop_name_available_v68(text) to authenticated;

-- Gestion de sa boutique (version 0050 + ignorer les boutiques fermées pour le nom).
create or replace function public.seller_manage_own_shop_v53(p_shop uuid, p_name text, p_action text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_shop public.shops%rowtype; v_name text; v_order_result jsonb := '{}'::jsonb;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into v_shop from public.shops where id = p_shop and owner_id = auth.uid() for update;
  if not found then raise exception 'shop_not_found_or_not_owned'; end if;
  if v_shop.kind = 'platform' or coalesce(v_shop.is_official, false) then raise exception 'official_shop_managed_by_admin'; end if;
  if p_action = 'rename' then
    v_name := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
    if char_length(v_name) < 2 or char_length(v_name) > 80 then raise exception 'shop_name_length_invalid'; end if;
    if exists (select 1 from public.shops s where s.id <> p_shop and s.status <> 'closed'
               and lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')) = lower(v_name)) then raise exception 'shop_name_taken'; end if;
    update public.shops set name = v_name where id = p_shop returning * into v_shop;
  elsif p_action = 'suspend' then
    if v_shop.status = 'closed' then raise exception 'shop_permanently_closed'; end if;
    update public.shops set status = 'suspended' where id = p_shop returning * into v_shop;
    v_order_result := public._freeze_shop_orders_v60(p_shop, auth.uid(), 'seller_shop_suspended');
  elsif p_action = 'close' then
    v_order_result := public._freeze_shop_orders_v60(p_shop, auth.uid(), 'seller_shop_closure_requested');
    update public.shops set status = 'suspended', deletion_requested_at = coalesce(deletion_requested_at, now()),
      deletion_scheduled_at = coalesce(deletion_scheduled_at, now() + interval '30 days'), deletion_review_status = 'pending_admin'
      where id = p_shop returning * into v_shop;
  else raise exception 'invalid_shop_action'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason)
    values (auth.uid(), 'seller_shop_' || p_action, 'shop', p_shop, 'Action vendeur; gel des commandes appliqué');
  return jsonb_build_object('id', v_shop.id, 'name', v_shop.name, 'status', v_shop.status, 'order_handling', v_order_result);
end $$;
revoke all on function public.seller_manage_own_shop_v53(uuid, text, text) from public, anon;
grant execute on function public.seller_manage_own_shop_v53(uuid, text, text) to authenticated;

-- Reprise d'une suspension VOLONTAIRE (le vendeur a lui-même cliqué « Suspendre »).
-- Une suspension décidée par l'administration ne peut être levée que par l'administration.
create or replace function public.seller_resume_shop_v68(p_shop uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare s public.shops%rowtype; v_last text;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into s from public.shops where id = p_shop and owner_id = auth.uid() for update;
  if not found then raise exception 'shop_not_found_or_not_owned'; end if;
  if s.kind = 'platform' or coalesce(s.is_official, false) then raise exception 'official_shop_managed_by_admin'; end if;
  if s.status <> 'suspended' then raise exception 'La boutique n''est pas suspendue.'; end if;
  if s.deletion_review_status in ('pending_admin', 'approved') then
    raise exception 'Une demande de suppression est en cours : attendez la décision de l''administration.';
  end if;
  select a.action into v_last
    from public.admin_audit_logs a
   where a.resource = 'shop' and a.resource_id = p_shop
     and a.action in ('seller_shop_suspend', 'set_status:suspended', 'shop_deletion_requested')
   order by a.created_at desc limit 1;
  if v_last is distinct from 'seller_shop_suspend' then
    raise exception 'Cette suspension a été décidée par l''administration : contactez le support pour la lever.';
  end if;
  if exists (select 1 from public.orders o join public.refund_requests r on r.order_id = o.id
              where o.shop_id = p_shop and r.status <> 'executed') then
    raise exception 'Des remboursements sont encore en cours : réessayez quand ils seront terminés.';
  end if;
  update public.shops set status = 'active' where id = p_shop returning * into s;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason)
    values (auth.uid(), 'seller_shop_resumed', 'shop', p_shop, 'Reprise après suspension volontaire');
  return jsonb_build_object('shop_id', s.id, 'status', s.status);
end;
$$;
revoke all on function public.seller_resume_shop_v68(uuid) from public, anon;
grant execute on function public.seller_resume_shop_v68(uuid) to authenticated;

commit;

notify pgrst, 'reload schema';
