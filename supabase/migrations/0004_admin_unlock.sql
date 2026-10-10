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
