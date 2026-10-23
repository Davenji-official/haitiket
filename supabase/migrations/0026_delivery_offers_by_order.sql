-- HAITIKET V16 : expose les offres actives depuis l'écran de suivi d'une commande.
-- Accès strictement limité au client propriétaire de la commande.
create or replace function public.list_delivery_price_offers_for_order(p_order uuid)
returns table(
  job_id uuid,
  offer_id uuid,
  courier_id uuid,
  courier_name text,
  amount_minor bigint,
  currency text,
  eta_minutes integer,
  note text,
  expires_at timestamptz,
  created_at timestamptz
)
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_job uuid;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not exists (
    select 1 from public.orders o
    where o.id = p_order and o.customer_id = v_uid and o.delivery_mode = 'delivery'
  ) then
    raise exception 'Commande introuvable ou accès refusé';
  end if;

  select j.id into v_job
  from public.delivery_jobs j
  where j.order_id = p_order and j.status = 'open'
  order by j.created_at desc
  limit 1;

  if v_job is null then return; end if;

  update public.delivery_job_offers f
  set status = 'expired', updated_at = now()
  where f.job_id = v_job and f.status = 'pending' and f.expires_at <= now();

  return query
  select f.job_id, f.id, f.courier_id,
         coalesce(p.display_name, 'Coursier HAITIKET'),
         f.amount_minor, f.currency, f.eta_minutes, f.note, f.expires_at, f.created_at
  from public.delivery_job_offers f
  left join public.profiles p on p.id = f.courier_id
  where f.job_id = v_job and f.status = 'pending' and f.expires_at > now()
  order by f.amount_minor asc, f.eta_minutes asc, f.created_at asc;
end $$;

revoke all on function public.list_delivery_price_offers_for_order(uuid) from public, anon;
grant execute on function public.list_delivery_price_offers_for_order(uuid) to authenticated;
