-- HAITIKET 0057 : correctifs de l'administration (re-exécutable sans risque).
--  1) admin_order_history_v47 : la fonction imbriquait des agrégats (count dans jsonb_agg) et échouait à chaque appel,
--     d'où le message « Vérifiez le SQL V47 » même quand la migration était exécutée.
--  2) Boutique officielle : tout administrateur DÉVERROUILLÉ peut gérer produits, médias, variantes et paliers
--     (jusqu'ici seuls le propriétaire ou certaines tables étaient autorisés -> erreur 42501 sur product_media).
--  3) Suppression de produit : fonction serveur qui vérifie réellement le droit et échoue bruyamment
--     (avant, la mise à jour était refusée sans erreur et le produit « supprimé » réapparaissait).
-- Aucun impact sur les portefeuilles, paiements ou commandes.

begin;

-- ---------- 1) Historique V47 ----------
create or replace function public.admin_order_history_v47(
  p_days integer default 30,
  p_currency text default 'ALL'
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_days integer := greatest(7, least(coalesce(p_days, 30), 90));
  v_currency text := upper(coalesce(p_currency, 'ALL'));
  v_result jsonb;
begin
  if auth.uid() is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : authentification et déverrouillage administrateur requis (re-saisissez le code secret)';
  end if;
  if v_currency not in ('ALL', 'HTG', 'USD') then
    raise exception 'Devise invalide : utilisez ALL, HTG ou USD';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'day', to_char(x.day_utc, 'YYYY-MM-DD'),
           'currency', x.currency,
           'order_count', x.order_count,
           'paid_order_count', x.paid_order_count,
           'paid_total_minor', x.paid_total_minor,
           'cancelled_count', x.cancelled_count
         ) order by x.day_utc, x.currency), '[]'::jsonb)
    into v_result
  from (
    select days.day_utc::date as day_utc,
           currencies.currency as currency,
           count(o.id)::integer as order_count,
           (count(o.id) filter (where o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')))::integer as paid_order_count,
           coalesce(sum(o.total_minor) filter (where o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')), 0)::bigint as paid_total_minor,
           (count(o.id) filter (where o.status in ('CANCELLED','REFUNDED')))::integer as cancelled_count
    from generate_series(
           (((now() at time zone 'UTC')::date - (v_days - 1))::timestamp),
           ((now() at time zone 'UTC')::date)::timestamp,
           interval '1 day'
         ) as days(day_utc)
    cross join unnest(array['HTG','USD']) as currencies(currency)
    left join public.orders o
      on (o.created_at at time zone 'UTC')::date = days.day_utc::date
     and o.currency = currencies.currency
     and (v_currency = 'ALL' or o.currency = v_currency)
    group by days.day_utc, currencies.currency
  ) x;

  return v_result;
end;
$$;
revoke all on function public.admin_order_history_v47(integer, text) from public, anon;
grant execute on function public.admin_order_history_v47(integer, text) to authenticated;

-- ---------- 2) Droits sur les produits de la boutique officielle ----------
create or replace function public.can_manage_product_v57(p_product uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.products p
    join public.shops s on s.id = p.shop_id
    where p.id = p_product
      and (s.owner_id = auth.uid() or (coalesce(s.is_official, false) and public.admin_unlocked()))
  );
$$;
revoke all on function public.can_manage_product_v57(uuid) from public, anon;
grant execute on function public.can_manage_product_v57(uuid) to authenticated;

-- Médias (reprend 0055/0056 : sans danger si déjà exécutées).
create or replace function public.can_write_product_media(p_product_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.products p
    join public.shops s on s.id = p.shop_id
    where p.id = p_product_id
      and s.status = 'active'
      and (s.owner_id = auth.uid() or (coalesce(s.is_official, false) and public.admin_unlocked()))
  );
$$;
revoke all on function public.can_write_product_media(uuid) from public, anon;
grant execute on function public.can_write_product_media(uuid) to authenticated;

drop policy if exists media_owner_write on public.product_media;
create policy media_owner_write on public.product_media
  for all to authenticated
  using (public.can_write_product_media(product_id))
  with check (public.can_write_product_media(product_id));

-- Variantes (taille/couleur/stock) et paliers de prix : même règle (propriétaire OU admin déverrouillé sur la boutique officielle).
drop policy if exists variants_owner_write on public.product_variants;
create policy variants_owner_write on public.product_variants
  for all to authenticated
  using (public.can_manage_product_v57(product_id))
  with check (public.can_manage_product_v57(product_id));

drop policy if exists tiers_owner_write on public.product_tiers;
create policy tiers_owner_write on public.product_tiers
  for all to authenticated
  using (public.can_manage_product_v57(product_id))
  with check (public.can_manage_product_v57(product_id));

-- Lecture : un admin déverrouillé voit aussi les brouillons / produits en pause de la boutique officielle
-- (sans cela, ses modifications étaient refusées sans message).
drop policy if exists products_read on public.products;
create policy products_read on public.products for select using (
  (status = 'published'
    and exists (select 1 from public.shops s where s.id = shop_id and s.status = 'active' and public.shop_plan_ok(s.id))
    and (source = 'marketplace' or paid_until > now()))
  or exists (
    select 1 from public.shops s
    where s.id = shop_id
      and (s.owner_id = auth.uid() or (coalesce(s.is_official, false) and public.admin_unlocked()))
  )
);

-- ---------- 3) Suppression (logique) d'un produit : vérifiée et bruyante ----------
create or replace function public.remove_product_v57(p_product uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_found uuid;
  v_official boolean;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;

  select p.id, coalesce(s.is_official, false)
    into v_found, v_official
  from public.products p
  join public.shops s on s.id = p.shop_id
  where p.id = p_product
    and (s.owner_id = auth.uid() or (coalesce(s.is_official, false) and public.admin_unlocked()))
  for update of p;

  if v_found is null then
    raise exception 'Produit introuvable ou accès refusé (si vous êtes administrateur, re-saisissez le code secret de la console)';
  end if;

  update public.products
     set status = 'removed', updated_at = now()
   where id = p_product and status <> 'removed';

  if v_official then
    insert into public.admin_audit_logs(actor, action, resource, resource_id, reason)
    values (auth.uid(), 'remove_official_product', 'product', p_product, 'Produit officiel retiré du catalogue');
  end if;

  return jsonb_build_object('product_id', p_product, 'status', 'removed');
end;
$$;
revoke all on function public.remove_product_v57(uuid) from public, anon;
grant execute on function public.remove_product_v57(uuid) to authenticated;

commit;

notify pgrst, 'reload schema';
