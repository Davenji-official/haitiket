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
