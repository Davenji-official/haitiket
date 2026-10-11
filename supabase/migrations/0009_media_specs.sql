-- HAITIKET lot 9 : galerie photos/vidéos, caractéristiques par catégorie, unité de vente.
-- Purement additif : ne modifie aucune fonction existante. Exécuter après 0001..0008.

alter table public.products add column if not exists attributes jsonb not null default '{}'::jsonb;
alter table public.products add column if not exists unit_label text not null default 'unité';

insert into public.categories (name)
select v.n from (values ('Pièces détachées'),('Femmes enceintes'),('Services autorisés'),('Électroménager et ménager')) v(n)
where not exists (select 1 from public.categories c where c.name = v.n);

create table public.product_media (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  url text not null check (url ~ '^https://'),
  kind text not null default 'image' check (kind in ('image','video')),
  position int not null default 0,
  created_at timestamptz not null default now()
);
create index on public.product_media (product_id, position);
alter table public.product_media enable row level security;
create policy media_read on public.product_media for select using (exists (select 1 from public.products p where p.id = product_id));
create policy media_owner_write on public.product_media for all
  using (exists (select 1 from public.products p join public.shops s on s.id = p.shop_id where p.id = product_id and s.owner_id = auth.uid()))
  with check (exists (select 1 from public.products p join public.shops s on s.id = p.shop_id where p.id = product_id and s.owner_id = auth.uid()));

create or replace function public._limit_media() returns trigger language plpgsql as $$
begin
  if (select count(*) from public.product_media where product_id = new.product_id) >= 10 then raise exception 'Maximum 10 photos/vidéos par produit'; end if;
  return new;
end $$;
drop trigger if exists product_media_limit on public.product_media;
create trigger product_media_limit before insert on public.product_media for each row execute function public._limit_media();

-- Le stockage accepte désormais de courtes vidéos (20 Mo max).
update storage.buckets set file_size_limit = 20971520,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime']
where id = 'media';
