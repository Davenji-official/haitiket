-- HAITIKET lot 12 : inscription complète (profil renseigné dès la création), consentements, suppression de compte.
-- À exécuter après 0001..0011.

alter table public.profiles add column if not exists city text;

create table if not exists public.consent_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('terms','privacy')),
  version text not null,
  accepted_at timestamptz not null default now()
);
alter table public.consent_records enable row level security;
drop policy if exists consents_self on public.consent_records;
create policy consents_self on public.consent_records for select using (user_id = auth.uid());

-- Le profil est créé avec les informations saisies à l'inscription (métadonnées du compte).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  ref uuid; rc text := upper(trim(coalesce(m->>'referral_code', '')));
begin
  if rc <> '' then select id into ref from public.profiles where referral_code = rc and id <> new.id; end if;
  insert into public.profiles(id, display_name, phone, city, referred_by)
  values (new.id, nullif(left(trim(coalesce(m->>'full_name', '')), 80), ''), nullif(left(trim(coalesce(m->>'phone', '')), 30), ''), nullif(left(trim(coalesce(m->>'city', '')), 80), ''), ref)
  on conflict (id) do nothing;
  if coalesce(m->>'accepted_terms', '') = 'true' then
    insert into public.consent_records(user_id, kind, version) values
      (new.id, 'terms', coalesce(nullif(m->>'terms_version', ''), '1')),
      (new.id, 'privacy', coalesce(nullif(m->>'terms_version', ''), '1'));
  end if;
  return new;
end $$;

-- Suppression de compte : anonymisation (les commandes et écritures comptables sont conservées sans données personnelles).
-- Appelée uniquement par la fonction Edge « delete-account » (clé de service).
create or replace function public.anonymize_account(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare o record; sh record;
begin
  if exists (select 1 from public.orders where customer_id = p_user and status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DISPUTED'))
     or exists (select 1 from public.orders od join public.shops s on s.id = od.shop_id where s.owner_id = p_user and od.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DISPUTED'))
     or exists (select 1 from public.delivery_jobs where courier_id = p_user and status in ('assigned','picked_up')) then
    raise exception 'Suppression impossible : des commandes ou livraisons sont encore en cours. Terminez-les d''abord.';
  end if;
  if exists (select 1 from public.refund_requests where user_id = p_user and status = 'to_execute') then
    raise exception 'Suppression impossible : un remboursement vous est encore dû. Contactez le support.';
  end if;
  for o in select id from public.orders where customer_id = p_user and status = 'PENDING_PAYMENT' loop
    perform public._cancel_order(o.id, p_user, 'account_deleted');
  end loop;
  perform set_config('haitiket.system', '1', true);
  for sh in select id from public.shops where owner_id = p_user loop
    update public.products set status = 'removed' where shop_id = sh.id and status <> 'removed';
    update public.shops set status = 'closed', name = 'Boutique fermée', slogan = null, logo_url = null, banner_url = null where id = sh.id;
  end loop;
  update public.courier_applications set status = 'rejected', full_name = 'Compte supprimé', phone = '-' where user_id = p_user;
  delete from public.courier_status where user_id = p_user;
  delete from public.addresses where user_id = p_user;
  delete from public.favorites where user_id = p_user;
  delete from public.shop_follows where user_id = p_user;
  delete from public.notifications where user_id = p_user;
  delete from public.product_events where user_id = p_user;
  delete from public.conversation_members where user_id = p_user;
  update public.profiles set display_name = 'Compte supprimé', phone = null, city = null, avatar_url = null, referral_code = null,
    suspended = true, suspended_reason = 'account_deleted' where id = p_user;
  insert into public.admin_audit_logs(actor, action, resource, resource_id) values (p_user, 'account_deleted', 'user', p_user);
end $$;
revoke all on function public.anonymize_account(uuid) from public, anon, authenticated;
