-- HAITIKET lot 3 : rôles admin, audit, modération, stockage des photos.

create table public.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','support')),
  primary key (user_id, role)
);
alter table public.user_roles enable row level security;
create policy roles_self_read on public.user_roles for select using (user_id = auth.uid());

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'admin') $$;
grant execute on function public.is_admin() to authenticated;

create table public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor uuid not null, action text not null, resource text not null, resource_id uuid, reason text,
  created_at timestamptz not null default now()
);
alter table public.admin_audit_logs enable row level security;
create policy audit_admin_read on public.admin_audit_logs for select using (public.is_admin());

create policy shops_admin_read on public.shops for select using (public.is_admin());
create policy courier_admin_read on public.courier_applications for select using (public.is_admin());
create policy listings_admin_read on public.listings for select using (public.is_admin());

create or replace function public.admin_set_status(p_kind text, p_id uuid, p_status text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'Accès refusé'; end if;
  if p_status in ('suspended','rejected','blocked','closed') and coalesce(trim(p_reason), '') = '' then raise exception 'Motif requis'; end if;
  if p_kind = 'shop' and p_status in ('pending','active','suspended','closed') then
    update public.shops set status = p_status where id = p_id;
  elsif p_kind = 'courier' and p_status in ('verifying','approved','rejected','suspended') then
    update public.courier_applications set status = p_status where id = p_id;
  elsif p_kind = 'listing' and p_status in ('published','blocked','draft') then
    update public.listings set status = p_status where id = p_id;
  else
    raise exception 'Action invalide';
  end if;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Élément introuvable'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'set_status:' || p_status, p_kind, p_id, p_reason);
end $$;
grant execute on function public.admin_set_status(text, uuid, text, text) to authenticated;

-- Photos : bucket public en lecture, écriture limitée au dossier de l'utilisateur, 3 Mo, JPEG/PNG/WebP.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
create policy media_read on storage.objects for select using (bucket_id = 'media');
create policy media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and owner = auth.uid());
-- HAITIKET lot 4 : déverrouillage admin par code secret vérifié CÔTÉ SERVEUR (le code n'est jamais dans l'application ni dans GitHub).
-- Après avoir exécuté ce fichier, définissez votre code une seule fois dans Supabase (voir instructions), sans l'enregistrer dans GitHub.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.admin_secret (id int primary key default 1 check (id = 1), code_hash text not null);
alter table public.admin_secret enable row level security;   -- aucune politique : illisible depuis l'application

create table if not exists public.admin_unlock_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  failed int not null default 0, locked_until timestamptz, unlocked_until timestamptz
);
alter table public.admin_unlock_state enable row level security;  -- aucune politique

create or replace function public.admin_unlocked() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() and exists (select 1 from public.admin_unlock_state where user_id = auth.uid() and unlocked_until > now()) $$;
grant execute on function public.admin_unlocked() to authenticated;

create or replace function public.admin_unlock(p_code text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare st public.admin_unlock_state; h text;
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'Accès refusé'; end if;
  insert into public.admin_unlock_state(user_id) values (auth.uid()) on conflict do nothing;
  select * into st from public.admin_unlock_state where user_id = auth.uid() for update;
  if st.locked_until is not null and st.locked_until > now() then raise exception 'Trop de tentatives. Réessayez plus tard.'; end if;
  select code_hash into h from public.admin_secret where id = 1;
  if h is null then raise exception 'Code admin non configuré'; end if;
  if crypt(coalesce(p_code, ''), h) = h then
    update public.admin_unlock_state set failed = 0, locked_until = null, unlocked_until = now() + interval '30 minutes' where user_id = auth.uid();
    insert into public.admin_audit_logs(actor, action, resource) values (auth.uid(), 'unlock', 'admin_panel');
    return true;
  end if;
  update public.admin_unlock_state set failed = failed + 1,
    locked_until = case when failed + 1 >= 5 then now() + interval '15 minutes' else null end,
    failed = case when failed + 1 >= 5 then 0 else failed + 1 end
  where user_id = auth.uid();
  insert into public.admin_audit_logs(actor, action, resource) values (auth.uid(), 'unlock_failed', 'admin_panel');
  return false;
end $$;
grant execute on function public.admin_unlock(text) to authenticated;

-- Toute la console exige désormais le rôle admin ET le déverrouillage récent.
drop policy if exists shops_admin_read on public.shops;
drop policy if exists courier_admin_read on public.courier_applications;
drop policy if exists listings_admin_read on public.listings;
drop policy if exists audit_admin_read on public.admin_audit_logs;
create policy shops_admin_read on public.shops for select using (public.admin_unlocked());
create policy courier_admin_read on public.courier_applications for select using (public.admin_unlocked());
create policy listings_admin_read on public.listings for select using (public.admin_unlocked());
create policy audit_admin_read on public.admin_audit_logs for select using (public.admin_unlocked());

create or replace function public.admin_set_status(p_kind text, p_id uuid, p_status text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_status in ('suspended','rejected','blocked','closed') and coalesce(trim(p_reason), '') = '' then raise exception 'Motif requis'; end if;
  if p_kind = 'shop' and p_status in ('pending','active','suspended','closed') then
    update public.shops set status = p_status where id = p_id;
  elsif p_kind = 'courier' and p_status in ('verifying','approved','rejected','suspended') then
    update public.courier_applications set status = p_status where id = p_id;
  elsif p_kind = 'listing' and p_status in ('published','blocked','draft') then
    update public.listings set status = p_status where id = p_id;
  else
    raise exception 'Action invalide';
  end if;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Élément introuvable'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'set_status:' || p_status, p_kind, p_id, p_reason);
end $$;
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
-- HAITIKET lot 6 : profil (avatar), abonnement boutique, tickets de support.
alter table public.profiles add column if not exists avatar_url text;
alter table public.shops add column if not exists plan_paid_until timestamptz;  -- abonnement boutique 20 USD / mois (renseigné par le futur webhook de paiement)

create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject text not null check (char_length(subject) between 3 and 120),
  message text not null check (char_length(message) between 5 and 2000),
  status text not null default 'OPEN' check (status in ('OPEN','ASSIGNED','RESOLVED','CLOSED')),
  admin_reply text,
  created_at timestamptz not null default now()
);
alter table public.support_tickets enable row level security;
create policy tickets_self_read on public.support_tickets for select using (user_id = auth.uid());
create policy tickets_self_insert on public.support_tickets for insert with check (user_id = auth.uid() and status = 'OPEN' and admin_reply is null);
create policy tickets_admin_read on public.support_tickets for select using (public.admin_unlocked());

create or replace function public.admin_reply_ticket(p_id uuid, p_reply text) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if coalesce(trim(p_reply), '') = '' then raise exception 'Réponse vide'; end if;
  update public.support_tickets set admin_reply = trim(p_reply), status = 'RESOLVED' where id = p_id;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Ticket introuvable'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id) values (auth.uid(), 'reply_ticket', 'support_ticket', p_id);
end $$;
grant execute on function public.admin_reply_ticket(uuid, text) to authenticated;
