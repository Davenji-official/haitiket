-- HAITIKET lot 5 : messagerie (temps réel) et espace livreur (disponibilité, missions, acceptation atomique).

-- ===== Messagerie =====
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  subject text not null,
  context_kind text not null check (context_kind in ('product','listing','order')),
  context_id uuid not null,
  created_at timestamptz not null default now()
);
create table public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (conversation_id, user_id)
);
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index on public.messages (conversation_id, created_at);
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;

create or replace function public.is_member(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.conversation_members where conversation_id = c and user_id = auth.uid()) $$;
grant execute on function public.is_member(uuid) to authenticated;

create policy conv_read on public.conversations for select using (public.is_member(id));
create policy members_read on public.conversation_members for select using (public.is_member(conversation_id));
create policy messages_read on public.messages for select using (public.is_member(conversation_id));
create policy messages_insert on public.messages for insert with check (sender_id = auth.uid() and public.is_member(conversation_id));

do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when others then raise notice 'Activez le temps réel pour la table messages dans Database > Replication'; end $$;

create or replace function public.start_conversation(p_kind text, p_ref uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid; subj text; cid uuid; cust uuid; owner uuid;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  if p_kind = 'product' then
    select s.owner_id, p.name into other, subj from public.products p join public.shops s on s.id = p.shop_id
      where p.id = p_ref and p.status = 'published' and s.status = 'active';
  elsif p_kind = 'listing' then
    select seller_id, title into other, subj from public.listings where id = p_ref and status = 'published';
  elsif p_kind = 'order' then
    select o.customer_id, s.owner_id into cust, owner from public.orders o join public.shops s on s.id = o.shop_id where o.id = p_ref;
    if uid = cust then other := owner; elsif uid = owner then other := cust; else raise exception 'Accès refusé'; end if;
    subj := 'Commande ' || left(p_ref::text, 8);
  else
    raise exception 'Type invalide';
  end if;
  if other is null then raise exception 'Introuvable'; end if;
  if other = uid then raise exception 'Vous ne pouvez pas vous écrire à vous-même'; end if;
  select c.id into cid from public.conversations c
    where c.context_kind = p_kind and c.context_id = p_ref
      and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = uid)
      and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = other)
    limit 1;
  if cid is null then
    insert into public.conversations(subject, context_kind, context_id) values (subj, p_kind, p_ref) returning id into cid;
    insert into public.conversation_members(conversation_id, user_id) values (cid, uid), (cid, other);
  end if;
  return cid;
end $$;
grant execute on function public.start_conversation(text, uuid) to authenticated;

-- ===== Livreurs =====
create table public.courier_status (
  user_id uuid primary key references auth.users(id) on delete cascade,
  available boolean not null default false, updated_at timestamptz not null default now()
);
alter table public.courier_status enable row level security;
create policy courier_status_self on public.courier_status for select using (user_id = auth.uid());

create or replace function public._is_approved_courier() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.courier_applications where user_id = auth.uid() and status = 'approved') $$;
revoke all on function public._is_approved_courier() from public, anon;
grant execute on function public._is_approved_courier() to authenticated;

create or replace function public.set_courier_available(p_available boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._is_approved_courier() then raise exception 'Candidature non approuvée'; end if;
  insert into public.courier_status(user_id, available) values (auth.uid(), p_available)
  on conflict (user_id) do update set available = excluded.available, updated_at = now();
end $$;
grant execute on function public.set_courier_available(boolean) to authenticated;

create table public.delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id),
  pickup_area text not null, dropoff_address text not null,
  pay_minor bigint not null check (pay_minor >= 0), currency text not null,
  status text not null default 'open' check (status in ('open','assigned','picked_up','delivered','cancelled')),
  courier_id uuid references auth.users(id), assigned_at timestamptz,
  created_at timestamptz not null default now()
);
create index on public.delivery_jobs (status, created_at);
alter table public.delivery_jobs enable row level security;
create policy jobs_own_read on public.delivery_jobs for select using (courier_id = auth.uid());

-- Créée uniquement par le système (futur webhook de paiement) : jamais appelable depuis l'application.
create or replace function public.create_delivery_job(p_order uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare o public.orders; city text; jid uuid;
begin
  select * into o from public.orders where id = p_order;
  if o.id is null or o.delivery_mode <> 'delivery' or o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') then
    raise exception 'Commande non éligible à une mission';
  end if;
  select coalesce(city, 'Zone non précisée') into city from public.shops where id = o.shop_id;
  insert into public.delivery_jobs(order_id, pickup_area, dropoff_address, pay_minor, currency)
  values (o.id, city, o.delivery_address, o.delivery_minor, o.currency) returning id into jid;
  return jid;
end $$;
revoke all on function public.create_delivery_job(uuid) from public, anon, authenticated;

create or replace function public.list_open_jobs() returns table (id uuid, pickup_area text, pay_minor bigint, currency text, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not public._is_approved_courier() then raise exception 'Candidature non approuvée'; end if;
  if not exists (select 1 from public.courier_status where user_id = auth.uid() and available) then return; end if;
  return query select j.id, j.pickup_area, j.pay_minor, j.currency, j.created_at from public.delivery_jobs j where j.status = 'open' order by j.created_at limit 50;
end $$;
grant execute on function public.list_open_jobs() to authenticated;

create or replace function public.accept_job(p_job uuid) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public._is_approved_courier() then raise exception 'Candidature non approuvée'; end if;
  if not exists (select 1 from public.courier_status where user_id = auth.uid() and available) then raise exception 'Activez votre disponibilité'; end if;
  if (select count(*) from public.delivery_jobs where courier_id = auth.uid() and status in ('assigned','picked_up')) >= 3 then
    raise exception 'Maximum 3 missions en cours';
  end if;
  update public.delivery_jobs set status = 'assigned', courier_id = auth.uid(), assigned_at = now() where id = p_job and status = 'open';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Mission déjà prise ou indisponible'; end if;
end $$;
grant execute on function public.accept_job(uuid) to authenticated;
