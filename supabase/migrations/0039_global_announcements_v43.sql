-- HAITIKET V43: annonces globales affichables dans l'application.
-- Appliquer après 0038_launch_readiness_audit_v29.sql.
create table if not exists public.platform_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 2 and 100),
  body text not null check (char_length(trim(body)) between 2 and 1200),
  severity text not null default 'info' check (severity in ('info','success','warning','urgent')),
  active boolean not null default true,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  deactivated_at timestamptz,
  check (ends_at is null or ends_at > starts_at)
);
create index if not exists platform_announcements_active_idx
  on public.platform_announcements (active, starts_at desc, created_at desc);
alter table public.platform_announcements enable row level security;
drop policy if exists platform_announcements_public_read on public.platform_announcements;
create policy platform_announcements_public_read on public.platform_announcements
  for select to anon, authenticated using (
    (active and starts_at <= now() and (ends_at is null or ends_at > now()))
    or (auth.uid() is not null and public.admin_unlocked())
  );
revoke insert, update, delete on public.platform_announcements from anon, authenticated;
grant select on public.platform_announcements to anon, authenticated;

-- Activer les événements Postgres Changes sans échouer si la table est déjà publiée.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'platform_announcements') then
    alter publication supabase_realtime add table public.platform_announcements;
  end if;
end $$;

-- Ajouter GIF au bucket média tout en conservant les formats image et vidéo existants.
update storage.buckets set allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','video/quicktime']
where id = 'media';

create or replace function public.admin_publish_announcement(
  p_title text, p_body text, p_severity text default 'info', p_ends_at timestamptz default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : déverrouillez la console administrateur';
  end if;
  if char_length(trim(coalesce(p_title,''))) not between 2 and 100 then raise exception 'Le titre doit contenir entre 2 et 100 caractères'; end if;
  if char_length(trim(coalesce(p_body,''))) not between 2 and 1200 then raise exception 'Le message doit contenir entre 2 et 1200 caractères'; end if;
  if p_severity not in ('info','success','warning','urgent') then raise exception 'Type d’annonce invalide'; end if;
  if p_ends_at is not null and p_ends_at <= now() then raise exception 'La date de fin doit être dans le futur'; end if;
  update public.platform_announcements set active=false, deactivated_at=now() where active=true;
  insert into public.platform_announcements(title,body,severity,active,starts_at,ends_at,created_by)
  values(trim(p_title),trim(p_body),p_severity,true,now(),p_ends_at,auth.uid()) returning id into v_id;
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
  values(auth.uid(),'publish_global_announcement','platform_announcement',v_id,left(trim(p_title),100));
  return v_id;
end $$;
revoke all on function public.admin_publish_announcement(text,text,text,timestamptz) from public, anon;
grant execute on function public.admin_publish_announcement(text,text,text,timestamptz) to authenticated;

create or replace function public.admin_deactivate_announcement(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : déverrouillez la console administrateur';
  end if;
  update public.platform_announcements set active=false,deactivated_at=now() where id=p_id and active=true;
  if not found then raise exception 'Annonce active introuvable'; end if;
  insert into public.admin_audit_logs(actor,action,resource,resource_id)
  values(auth.uid(),'deactivate_global_announcement','platform_announcement',p_id);
end $$;
revoke all on function public.admin_deactivate_announcement(uuid) from public, anon;
grant execute on function public.admin_deactivate_announcement(uuid) to authenticated;
