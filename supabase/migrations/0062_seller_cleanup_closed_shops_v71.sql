-- HAITIKET 0062 : (1) « Retirer de ma liste » pour les commandes terminées/annulées (vendeur et client),
-- (2) liste admin des boutiques sans les boutiques fermées par défaut, (3) suppression définitive d'une boutique fermée
-- (uniquement si elle n'a aucun historique). Ré-exécutable sans risque. N'efface aucun historique financier.

begin;

-- ---------- 1) Commandes retirées de MA liste ----------
create table if not exists public.hidden_orders_v71 (
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (user_id, order_id)
);
alter table public.hidden_orders_v71 enable row level security;  -- accès uniquement via les fonctions ci-dessous

create or replace function public.hide_order_v71(p_order uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare o public.orders; v_owner uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into o from public.orders where id = p_order;
  if o.id is null then raise exception 'order_not_found'; end if;
  select s.owner_id into v_owner from public.shops s where s.id = o.shop_id;
  if auth.uid() <> o.customer_id and auth.uid() is distinct from v_owner then raise exception 'order_not_found'; end if;
  if o.status not in ('CANCELLED', 'REFUNDED', 'COMPLETED') then raise exception 'order_not_finished'; end if;
  insert into public.hidden_orders_v71(user_id, order_id) values (auth.uid(), p_order) on conflict do nothing;
end;
$$;
revoke all on function public.hide_order_v71(uuid) from public, anon;
grant execute on function public.hide_order_v71(uuid) to authenticated;

-- Nettoyage en un geste : retire de ma liste toutes les commandes annulées/remboursées d'une de mes boutiques.
create or replace function public.hide_cancelled_orders_v71(p_shop uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_count integer;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if not exists (select 1 from public.shops s where s.id = p_shop and s.owner_id = auth.uid()) then raise exception 'shop_not_found'; end if;
  with ins as (
    insert into public.hidden_orders_v71(user_id, order_id)
    select auth.uid(), o.id from public.orders o
     where o.shop_id = p_shop and o.status in ('CANCELLED', 'REFUNDED')
    on conflict do nothing
    returning 1
  )
  select count(*) into v_count from ins;
  return coalesce(v_count, 0);
end;
$$;
revoke all on function public.hide_cancelled_orders_v71(uuid) from public, anon;
grant execute on function public.hide_cancelled_orders_v71(uuid) to authenticated;

create or replace function public.hidden_order_ids_v71()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(h.order_id), '[]'::jsonb) from public.hidden_orders_v71 h where h.user_id = auth.uid();
$$;
revoke all on function public.hidden_order_ids_v71() from public, anon;
grant execute on function public.hidden_order_ids_v71() to authenticated;

-- ---------- 2) Liste admin des boutiques : fermées masquées par défaut ----------
create or replace function public.admin_shop_requests_v71(p_include_closed boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(t) order by t.pending_first desc, t.created_at desc)
    from (
      select s.id, s.name, s.city, s.status, s.verified_at, s.deletion_requested_at, s.deletion_scheduled_at,
             s.deletion_review_status, s.created_at, s.owner_id,
             (s.status = 'pending') as pending_first,
             coalesce(nullif(btrim(p.display_name), ''), 'Nom non renseigné') as owner_name,
             p.phone as owner_phone,
             coalesce((select iv.status from public.identity_verifications iv
                        where iv.user_id = s.owner_id order by iv.created_at desc limit 1), 'none') as kyc_status
        from public.shops s
        left join public.profiles p on p.id = s.owner_id
       where coalesce(s.kind, 'pro') = 'pro' and not coalesce(s.is_official, false)
         and (p_include_closed or s.status <> 'closed')
       order by (s.status = 'pending') desc, s.created_at desc
       limit 150
    ) t
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.admin_shop_requests_v71(boolean) from public, anon;
grant execute on function public.admin_shop_requests_v71(boolean) to authenticated;

-- ---------- 3) Suppression définitive d'une boutique FERMÉE (sans historique) ----------
create or replace function public.admin_purge_closed_shop_v71(p_shop uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare s public.shops%rowtype;
begin
  if not public.admin_unlocked() then raise exception 'admin_console_locked'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'admin_reason_required'; end if;
  select * into s from public.shops where id = p_shop for update;
  if not found then raise exception 'shop_not_found'; end if;
  if coalesce(s.is_official, false) or coalesce(s.kind, 'pro') = 'platform' then raise exception 'official_shop_managed_by_admin'; end if;
  if s.status <> 'closed' then raise exception 'only_closed_shop_can_be_purged'; end if;
  begin
    delete from public.shops where id = p_shop;
  exception when foreign_key_violation then
    insert into public.admin_audit_logs(actor, action, resource, resource_id, reason)
      values (auth.uid(), 'shop_purge_blocked_history', 'shop', p_shop, left(p_reason, 200));
    return jsonb_build_object('shop_id', p_shop, 'purged', false, 'reason', 'has_history');
  end;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason)
    values (auth.uid(), 'shop_purged', 'shop', p_shop, left(p_reason, 200));
  return jsonb_build_object('shop_id', p_shop, 'purged', true);
end;
$$;
revoke all on function public.admin_purge_closed_shop_v71(uuid, text) from public, anon;
grant execute on function public.admin_purge_closed_shop_v71(uuid, text) to authenticated;

commit;

notify pgrst, 'reload schema';
