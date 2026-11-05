-- HAITIKET V76 — prise de contrôle des comptes BLOQUÉS ou SUPPRIMÉS par l'administration.
-- Cause du blocage : admin_manage_user pose auth.users.banned_until (+100 ans) ; Supabase Auth refuse alors tout nouveau jeton,
-- y compris celui d'une prise de contrôle. Solution : session de support de 20 minutes qui lève le blocage, puis le rétablit
-- (à la sortie de l'admin, ou automatiquement à l'expiration). Les gardes métier (compte suspendu : pas de commande ni de message) restent actives.

create table if not exists public.support_sessions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  admin_id uuid not null,
  banned_until_before timestamptz,
  expires_at timestamptz not null,
  restored boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists support_sessions_pending_idx on public.support_sessions(restored, expires_at);
alter table public.support_sessions enable row level security;
revoke all on public.support_sessions from anon, authenticated;

create or replace function public.restore_expired_support_bans() returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update auth.users u set banned_until = s.banned_until_before
  from public.support_sessions s
  where s.user_id = u.id and not s.restored and s.expires_at < now();
  get diagnostics n = row_count;
  update public.support_sessions set restored = true where not restored and expires_at < now();
  return n;
end $$;
revoke all on function public.restore_expired_support_bans() from public, anon, authenticated;

-- Auto-guérison : toute activité d'un utilisateur (toutes les ~60 s) rétablit les blocages expirés.
create or replace function public.touch_presence() returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set last_seen_at = now()
  where id = auth.uid() and (last_seen_at is null or last_seen_at < now() - interval '45 seconds');
  perform public.restore_expired_support_bans();
end $$;
revoke all on function public.touch_presence() from public, anon;
grant execute on function public.touch_presence() to authenticated;

create or replace function public.admin_begin_support_session(p_user uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_banned timestamptz; v_status text; v_was boolean;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_user = auth.uid() then raise exception 'Compte déjà connecté'; end if;
  if exists(select 1 from public.user_roles where user_id = p_user and role = 'admin') then raise exception 'Prise de contrôle interdite sur un administrateur'; end if;
  if char_length(btrim(coalesce(p_reason,''))) < 5 then raise exception 'Motif détaillé requis (5 caractères minimum)'; end if;
  perform public.restore_expired_support_bans();

  select banned_until into v_banned from auth.users where id = p_user;
  select account_status into v_status from public.profiles where id = p_user;
  if not found then raise exception 'Compte introuvable'; end if;
  v_was := v_banned is not null and v_banned > now();

  if v_was then
    insert into public.support_sessions(user_id, admin_id, banned_until_before, expires_at, restored)
    values (p_user, auth.uid(), v_banned, now() + interval '20 minutes', false)
    on conflict (user_id) do update set admin_id = excluded.admin_id, banned_until_before = excluded.banned_until_before,
      expires_at = excluded.expires_at, restored = false;
    update auth.users set banned_until = null where id = p_user;
  end if;

  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason)
  values (auth.uid(), 'impersonate_user', 'user', p_user, left(p_reason || case when v_was then ' [compte ' || coalesce(v_status,'bloqué') || ', accès temporaire 20 min]' else '' end, 200));
  return jsonb_build_object('was_banned', v_was, 'account_status', v_status);
end $$;
revoke all on function public.admin_begin_support_session(uuid,text) from public, anon;
grant execute on function public.admin_begin_support_session(uuid,text) to authenticated;

create or replace function public.admin_end_support_session(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  update auth.users u set banned_until = s.banned_until_before
  from public.support_sessions s where s.user_id = p_user and u.id = p_user and not s.restored;
  update public.support_sessions set restored = true where user_id = p_user and not restored;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason)
  values (auth.uid(), 'end_support_session', 'user', p_user, 'fin de la prise de contrôle');
end $$;
revoke all on function public.admin_end_support_session(uuid) from public, anon;
grant execute on function public.admin_end_support_session(uuid) to authenticated;
