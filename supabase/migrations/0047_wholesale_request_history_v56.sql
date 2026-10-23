-- V56: immutable, participant-readable event history for wholesale requests.
-- No payment or wallet mutation is performed by this migration.
create table if not exists public.wholesale_request_events (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.wholesale_requests(id) on delete restrict,
  seller_shop_id uuid not null references public.shops(id) on delete restrict,
  buyer_shop_id uuid not null references public.shops(id) on delete restrict,
  event_type text not null check (event_type in (
    'request_created','request_accepted','request_rejected','request_cancelled',
    'reservation_expired','goods_handed_over','reservation_deadline_set','request_updated'
  )),
  old_status text,
  new_status text not null,
  quantity integer not null check (quantity between 2 and 10000),
  unit_price_minor bigint not null check (unit_price_minor > 0),
  total_minor bigint not null check (total_minor > 0),
  currency text not null check (currency in ('HTG','USD')),
  expires_at timestamptz,
  actor_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists wholesale_request_events_request_time_v56
  on public.wholesale_request_events(request_id, created_at desc, id desc);
create index if not exists wholesale_request_events_seller_time_v56
  on public.wholesale_request_events(seller_shop_id, created_at desc);
create index if not exists wholesale_request_events_buyer_time_v56
  on public.wholesale_request_events(buyer_shop_id, created_at desc);

alter table public.wholesale_request_events enable row level security;
drop policy if exists wholesale_request_events_participant_read_v56 on public.wholesale_request_events;
create policy wholesale_request_events_participant_read_v56
  on public.wholesale_request_events for select to authenticated
  using (
    exists(select 1 from public.shops s where s.id=wholesale_request_events.seller_shop_id and s.owner_id=auth.uid())
    or exists(select 1 from public.shops s where s.id=wholesale_request_events.buyer_shop_id and s.owner_id=auth.uid())
  );
revoke all on public.wholesale_request_events from public, anon, authenticated;
grant select on public.wholesale_request_events to authenticated;
revoke all on sequence public.wholesale_request_events_id_seq from public, anon, authenticated;

create or replace function public.capture_wholesale_request_event_v56()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_event_type text;
begin
  if tg_op = 'INSERT' then
    v_event_type := 'request_created';
  else
    if new.status is distinct from old.status then
      v_event_type := case new.status
        when 'accepted' then 'request_accepted'
        when 'rejected' then 'request_rejected'
        when 'cancelled' then 'request_cancelled'
        when 'expired' then 'reservation_expired'
        when 'fulfilled' then 'goods_handed_over'
        else 'request_updated'
      end;
    elsif new.expires_at is distinct from old.expires_at then
      v_event_type := 'reservation_deadline_set';
    elsif new.quantity is distinct from old.quantity
       or new.unit_price_minor is distinct from old.unit_price_minor
       or new.currency is distinct from old.currency then
      v_event_type := 'request_updated';
    else
      return new;
    end if;
  end if;

  insert into public.wholesale_request_events(
    request_id,seller_shop_id,buyer_shop_id,event_type,old_status,new_status,
    quantity,unit_price_minor,total_minor,currency,expires_at,actor_id
  ) values (
    new.id,new.seller_shop_id,new.buyer_shop_id,v_event_type,
    case when tg_op='UPDATE' then old.status else null end,
    new.status,new.quantity,new.unit_price_minor,new.total_minor,new.currency,
    new.expires_at,auth.uid()
  );
  return new;
end $$;
revoke all on function public.capture_wholesale_request_event_v56() from public, anon, authenticated;

drop trigger if exists wholesale_request_event_capture_v56 on public.wholesale_requests;
create trigger wholesale_request_event_capture_v56
after insert or update on public.wholesale_requests
for each row execute function public.capture_wholesale_request_event_v56();

-- Backfill a baseline event for requests created before V56; does not invent past transitions.
insert into public.wholesale_request_events(
  request_id,seller_shop_id,buyer_shop_id,event_type,old_status,new_status,
  quantity,unit_price_minor,total_minor,currency,expires_at,actor_id,created_at
)
select r.id,r.seller_shop_id,r.buyer_shop_id,'request_created',null,r.status,
       r.quantity,r.unit_price_minor,r.total_minor,r.currency,r.expires_at,null,r.created_at
from public.wholesale_requests r
where not exists (
  select 1 from public.wholesale_request_events e
  where e.request_id=r.id and e.event_type='request_created'
);
