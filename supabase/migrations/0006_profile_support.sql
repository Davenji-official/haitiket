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
