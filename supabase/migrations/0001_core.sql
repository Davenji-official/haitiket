-- HAITIKET lot 1 : socle (profils, boutiques, catalogue, bazar, favoris, candidatures livreurs)
-- Montants en unités mineures (centimes). RLS activée partout : refus par défaut.
create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text, phone text, created_at timestamptz not null default now()
);
create table public.shops (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 80),
  city text, status text not null default 'pending' check (status in ('draft','pending','active','suspended','closed')),
  created_at timestamptz not null default now()
);
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null, parent_id uuid references public.categories(id), active boolean not null default true
);
create table public.products (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  category_id uuid references public.categories(id),
  name text not null, description text,
  price_minor bigint not null check (price_minor >= 0), currency text not null default 'HTG',
  image_url text, stock int not null default 0 check (stock >= 0),
  status text not null default 'draft' check (status in ('draft','published','paused','removed')),
  created_at timestamptz not null default now()
);
create index on public.products (status, created_at desc);
create table public.listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  title text not null, description text,
  price_minor bigint not null check (price_minor > 0), currency text not null default 'HTG',
  condition text, city text, image_url text,
  status text not null default 'draft' check (status in ('draft','moderation','published','blocked','sold','expired','deleted')),
  paid_until timestamptz, created_at timestamptz not null default now()
);
create table public.favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  primary key (user_id, product_id)
);
create table public.courier_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  full_name text not null, phone text not null, transport text not null, zone text not null,
  status text not null default 'submitted' check (status in ('submitted','verifying','approved','rejected','suspended')),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin insert into public.profiles(id) values (new.id) on conflict do nothing; return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.shops enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.listings enable row level security;
alter table public.favorites enable row level security;
alter table public.courier_applications enable row level security;

create policy profiles_self on public.profiles for all using (id = auth.uid()) with check (id = auth.uid());
create policy shops_read on public.shops for select using (status = 'active' or owner_id = auth.uid());
create policy shops_insert on public.shops for insert with check (owner_id = auth.uid() and status = 'pending');
create policy categories_read on public.categories for select using (active);
create policy products_read on public.products for select using (
  (status = 'published' and exists (select 1 from public.shops s where s.id = shop_id and s.status = 'active'))
  or exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = auth.uid()));
create policy products_write on public.products for all
  using (exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = auth.uid() and s.status = 'active'))
  with check (exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = auth.uid() and s.status = 'active'));
create policy listings_read on public.listings for select using (status = 'published' or seller_id = auth.uid());
create policy listings_insert on public.listings for insert with check (seller_id = auth.uid() and status = 'draft');
create policy listings_update on public.listings for update using (seller_id = auth.uid() and status in ('draft','published')) with check (seller_id = auth.uid() and status in ('draft','published'));
create policy favorites_self on public.favorites for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy courier_self_read on public.courier_applications for select using (user_id = auth.uid());
create policy courier_self_insert on public.courier_applications for insert with check (user_id = auth.uid() and status = 'submitted');
