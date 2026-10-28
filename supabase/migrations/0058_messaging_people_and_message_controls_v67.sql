-- HAITIKET 0058 : messagerie professionnelle (photos/noms des interlocuteurs, suppression pour soi / pour tous).
-- Ré-exécutable sans risque. Réutilise les colonnes de 0013 (conversation_user_state, messages.deleted_at).
-- Pourquoi : la table profiles est privée (RLS « profiles_self »). L'application ne pouvait donc jamais lire la photo d'un
-- autre utilisateur ; ces fonctions serveur renvoient UNIQUEMENT nom + photo (et logo de boutique) des membres d'une
-- conversation à laquelle l'appelant participe.

begin;

-- « Supprimer pour moi » un message précis (les autres participants le voient toujours).
create table if not exists public.hidden_messages_v67 (
  user_id uuid not null references auth.users(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (user_id, message_id)
);
alter table public.hidden_messages_v67 enable row level security;   -- aucune politique : accès uniquement via les fonctions ci-dessous

-- Copie du texte d'un message « supprimé pour tous » (litiges / audit ; illisible depuis l'application).
create table if not exists public.message_originals_v67 (
  message_id uuid primary key references public.messages(id) on delete cascade,
  original_body text not null,
  deleted_by uuid not null references auth.users(id),
  deleted_at timestamptz not null default now()
);
alter table public.message_originals_v67 enable row level security;

-- Boutique liée à la conversation (produit, annonce ou commande).
create or replace function public._conversation_shop_v67(p_conv uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.shop_id from public.products p join public.conversations c on c.context_id = p.id
      where c.id = p_conv and c.context_kind in ('product','listing')),
    (select o.shop_id from public.orders o join public.conversations c on c.context_id = o.id
      where c.id = p_conv and c.context_kind = 'order')
  );
$$;
revoke all on function public._conversation_shop_v67(uuid) from public, anon, authenticated;

-- Participants d'une conversation : nom, photo, et boutique (nom + logo) si la personne est le vendeur concerné.
create or replace function public.conversation_people_v67(p_conv uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_shop uuid;
begin
  if auth.uid() is null or not public.is_member(p_conv) then
    raise exception 'Accès refusé à cette conversation';
  end if;
  v_shop := public._conversation_shop_v67(p_conv);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'user_id', m.user_id,
      'is_me', m.user_id = auth.uid(),
      'name', case when sh.id is not null then sh.name else coalesce(nullif(trim(pr.display_name), ''), 'Utilisateur HAITIKET') end,
      'person_name', coalesce(nullif(trim(pr.display_name), ''), 'Utilisateur HAITIKET'),
      'avatar_url', case when sh.logo_url is not null and sh.logo_url <> '' then sh.logo_url else pr.avatar_url end,
      'person_avatar_url', pr.avatar_url,
      'is_shop', sh.id is not null
    ))
    from public.conversation_members m
    left join public.profiles pr on pr.id = m.user_id
    left join public.shops sh on sh.id = v_shop and sh.owner_id = m.user_id
    where m.conversation_id = p_conv
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.conversation_people_v67(uuid) from public, anon;
grant execute on function public.conversation_people_v67(uuid) to authenticated;

-- Boîte de réception : interlocuteur (photo/nom), dernier message, discussions masquées exclues.
create or replace function public.my_conversations_v67()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select coalesce(jsonb_agg(to_jsonb(t) order by t.last_at desc), '[]'::jsonb) into v
  from (
    select c.id, c.subject, c.context_kind, c.context_id, c.created_at,
           lm.body as last_body,
           (lm.deleted_at is not null) as last_deleted,
           coalesce(lm.created_at, c.created_at) as last_at,
           o.user_id as other_user_id,
           case when sh.id is not null and sh.owner_id = o.user_id then sh.name
                else coalesce(nullif(trim(pr.display_name), ''), 'Utilisateur HAITIKET') end as other_name,
           case when sh.id is not null and sh.owner_id = o.user_id and sh.logo_url is not null and sh.logo_url <> '' then sh.logo_url
                else pr.avatar_url end as other_avatar,
           (sh.id is not null and sh.owner_id = o.user_id) as other_is_shop
    from public.conversations c
    join public.conversation_members me on me.conversation_id = c.id and me.user_id = auth.uid()
    left join lateral (
      select m.body, m.created_at, m.deleted_at from public.messages m
      where m.conversation_id = c.id order by m.created_at desc limit 1
    ) lm on true
    left join lateral (
      select cm.user_id from public.conversation_members cm
      where cm.conversation_id = c.id and cm.user_id <> auth.uid() order by cm.user_id limit 1
    ) o on true
    left join public.profiles pr on pr.id = o.user_id
    left join public.shops sh on sh.id = public._conversation_shop_v67(c.id)
    where not exists (
      select 1 from public.conversation_user_state s
      where s.conversation_id = c.id and s.user_id = auth.uid()
        and s.hidden_at is not null and s.hidden_at >= coalesce(lm.created_at, c.created_at)
    )
    order by coalesce(lm.created_at, c.created_at) desc
    limit 100
  ) t;
  return v;
end;
$$;
revoke all on function public.my_conversations_v67() from public, anon;
grant execute on function public.my_conversations_v67() to authenticated;

-- Masquer une discussion dans MA boîte (elle reste chez l'autre personne et pour les litiges).
create or replace function public.hide_conversation_v67(p_conv uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_member(p_conv) then raise exception 'Accès refusé à cette conversation'; end if;
  insert into public.conversation_user_state(conversation_id, user_id, hidden_at)
  values (p_conv, auth.uid(), now())
  on conflict (conversation_id, user_id) do update set hidden_at = now();
end;
$$;
revoke all on function public.hide_conversation_v67(uuid) from public, anon;
grant execute on function public.hide_conversation_v67(uuid) to authenticated;

-- Supprimer un message pour moi.
create or replace function public.hide_message_v67(p_message uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_conv uuid;
begin
  select conversation_id into v_conv from public.messages where id = p_message;
  if v_conv is null or auth.uid() is null or not public.is_member(v_conv) then raise exception 'Message introuvable ou accès refusé'; end if;
  insert into public.hidden_messages_v67(user_id, message_id) values (auth.uid(), p_message) on conflict do nothing;
end;
$$;
revoke all on function public.hide_message_v67(uuid) from public, anon;
grant execute on function public.hide_message_v67(uuid) to authenticated;

-- Supprimer pour tous (mes messages, dans les 15 minutes) : le texte est remplacé, l'original est archivé pour les litiges.
create or replace function public.delete_message_for_all_v67(p_message uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare m public.messages;
begin
  select * into m from public.messages where id = p_message for update;
  if m.id is null or m.sender_id <> auth.uid() or not public.is_member(m.conversation_id) then
    raise exception 'Vous ne pouvez supprimer que vos propres messages';
  end if;
  if m.deleted_at is not null then return; end if;
  if m.created_at < now() - interval '15 minutes' then
    raise exception 'Suppression pour tous possible pendant 15 minutes seulement : utilisez « Supprimer pour moi »';
  end if;
  insert into public.message_originals_v67(message_id, original_body, deleted_by) values (m.id, m.body, auth.uid()) on conflict do nothing;
  update public.messages set body = 'Message supprimé', deleted_at = now(), deleted_by = auth.uid() where id = m.id;
end;
$$;
revoke all on function public.delete_message_for_all_v67(uuid) from public, anon;
grant execute on function public.delete_message_for_all_v67(uuid) to authenticated;

create or replace function public.hidden_message_ids_v67(p_conv uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_member(p_conv) then raise exception 'Accès refusé à cette conversation'; end if;
  return coalesce((
    select jsonb_agg(h.message_id) from public.hidden_messages_v67 h
    join public.messages m on m.id = h.message_id
    where h.user_id = auth.uid() and m.conversation_id = p_conv
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.hidden_message_ids_v67(uuid) from public, anon;
grant execute on function public.hidden_message_ids_v67(uuid) to authenticated;

commit;

notify pgrst, 'reload schema';
