-- HAITIKET V45: consultation sécurisée du journal d'audit depuis la console.
-- Migration additive et en lecture seule; aucune transaction métier n'est modifiée.
create index if not exists admin_audit_logs_created_at_idx
  on public.admin_audit_logs (created_at desc);

create or replace function public.admin_read_audit_log(p_take integer default 100)
returns table (
  id uuid,
  actor uuid,
  action text,
  resource text,
  resource_id uuid,
  reason text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : déverrouillez la console administrateur';
  end if;
  return query
    select l.id, l.actor, l.action, l.resource, l.resource_id, l.reason, l.created_at
    from public.admin_audit_logs l
    order by l.created_at desc
    limit greatest(1, least(coalesce(p_take, 100), 200));
end;
$$;
revoke all on function public.admin_read_audit_log(integer) from public, anon;
grant execute on function public.admin_read_audit_log(integer) to authenticated;
comment on function public.admin_read_audit_log(integer) is
  'Lecture limitée du journal admin après authentification et déverrouillage; aucune mutation.';
