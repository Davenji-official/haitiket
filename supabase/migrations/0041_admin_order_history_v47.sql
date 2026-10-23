-- HAITIKET V47: séries historiques agrégées, en lecture seule et séparées par devise.
create index if not exists orders_created_at_currency_v47_idx
  on public.orders (created_at, currency);

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
    raise exception 'Accès refusé : authentification et déverrouillage administrateur requis';
  end if;
  if v_currency not in ('ALL', 'HTG', 'USD') then
    raise exception 'Devise invalide : utilisez ALL, HTG ou USD';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'day', to_char(days.day_utc, 'YYYY-MM-DD'),
    'currency', currencies.currency,
    'order_count', count(o.id),
    'paid_order_count', count(o.id) filter (where o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')),
    'paid_total_minor', coalesce(sum(o.total_minor) filter (where o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')), 0),
    'cancelled_count', count(o.id) filter (where o.status in ('CANCELLED','REFUNDED'))
  ) order by days.day_utc, currencies.currency), '[]'::jsonb)
  into v_result
  from generate_series(
    ((now() at time zone 'UTC')::date - (v_days - 1)),
    (now() at time zone 'UTC')::date,
    interval '1 day'
  ) as days(day_utc)
  cross join unnest(array['HTG','USD']) as currencies(currency)
  left join public.orders o
    on (o.created_at at time zone 'UTC')::date = days.day_utc::date
   and o.currency = currencies.currency
   and (v_currency = 'ALL' or o.currency = v_currency);

  return v_result;
end;
$$;
revoke all on function public.admin_order_history_v47(integer, text) from public, anon;
grant execute on function public.admin_order_history_v47(integer, text) to authenticated;
comment on function public.admin_order_history_v47(integer, text) is
  'Historique journalier des commandes, limité à 90 jours, en lecture seule et séparé par devise.';
