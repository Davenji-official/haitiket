-- HAITIKET lot 13 : variantes plus riches, galerie et contrôles de messagerie.
-- À appliquer UNIQUEMENT après les migrations 0001 à 0012 et les blocs SQL A/B/C validés.

-- Les options existent déjà via product_variants et product_tiers. Ces colonnes
-- complètent le modèle pour les produits vendus à l'unité, en lot ou pour un public précis.
alter table public.product_variants add column if not exists audience text;
alter table public.product_variants add column if not exists sku text;
alter table public.product_variants add column if not exists unit_label text not null default 'unité';
alter table public.product_variants add column if not exists price_minor bigint;
alter table public.product_variants add column if not exists attributes jsonb not null default '{}'::jsonb;
do $$ begin
  alter table public.product_variants add constraint product_variants_price_nonnegative
    check (price_minor is null or price_minor >= 0);
exception when duplicate_object then null; end $$;

-- Une unité de vente explicite pour le produit (unité, paire, lot, paquet, carton...).
alter table public.products add column if not exists unit_label text not null default 'unité';
alter table public.products add column if not exists audience text;
alter table public.products add column if not exists attributes jsonb not null default '{}'::jsonb;
alter table public.products add column if not exists updated_at timestamptz not null default now();

create index if not exists products_shop_updated_idx on public.products(shop_id, updated_at desc);

-- Mise à jour de la date d'édition pour suivre les changements du catalogue.
create or replace function public._haitiket_touch_updated_at() returns trigger
language plpgsql set search_path = public as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists products_touch_updated_at on public.products;
create trigger products_touch_updated_at before update on public.products
for each row execute function public._haitiket_touch_updated_at();

-- Permettre à l'utilisateur de supprimer une notification de SON propre centre de notifications.
-- La suppression ne supprime pas la commande ou l'événement source.
drop policy if exists notifications_self_delete on public.notifications;
create policy notifications_self_delete on public.notifications
for delete using (user_id = auth.uid());

-- Masquage d'une discussion dans la boîte de réception de chaque participant,
-- sans effacer la discussion chez l'autre personne ni les preuves liées à une commande.
create table if not exists public.conversation_user_state (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  hidden_at timestamptz,
  primary key (conversation_id, user_id)
);
alter table public.conversation_user_state enable row level security;
drop policy if exists conversation_user_state_read_self on public.conversation_user_state;
create policy conversation_user_state_read_self on public.conversation_user_state
for select using (user_id = auth.uid());
drop policy if exists conversation_user_state_insert_self on public.conversation_user_state;
create policy conversation_user_state_insert_self on public.conversation_user_state
for insert with check (user_id = auth.uid() and public.is_member(conversation_id));
drop policy if exists conversation_user_state_update_self on public.conversation_user_state;
create policy conversation_user_state_update_self on public.conversation_user_state
for update using (user_id = auth.uid() and public.is_member(conversation_id))
with check (user_id = auth.uid() and public.is_member(conversation_id));

-- Suppression logique d'un message par son auteur : conserve le contexte d'audit.
alter table public.messages add column if not exists deleted_at timestamptz;
alter table public.messages add column if not exists deleted_by uuid references auth.users(id);
drop policy if exists messages_sender_soft_delete on public.messages;
create policy messages_sender_soft_delete on public.messages
for update using (sender_id = auth.uid() and public.is_member(conversation_id))
with check (sender_id = auth.uid() and public.is_member(conversation_id));

comment on column public.products.unit_label is 'Unité vendue, par exemple unité, paire, lot, paquet ou carton.';
comment on column public.products.audience is 'Public cible, par exemple homme, femme, enfant, adolescent ou unisexe.';
comment on column public.product_variants.audience is 'Public cible spécifique à cette variante si nécessaire.';
comment on column public.product_variants.price_minor is 'Prix spécifique à la variante; null signifie utiliser le prix du produit.';
comment on table public.conversation_user_state is 'État individuel de visibilité des discussions dans la boîte de réception.';
