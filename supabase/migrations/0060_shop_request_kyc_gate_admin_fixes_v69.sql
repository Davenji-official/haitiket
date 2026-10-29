-- HAITIKET 0060 : (1) une demande de boutique exige une vérification d'identité déjà envoyée,
-- (2) file des demandes de boutique avec propriétaire + statut KYC, (3) liste des transactions portefeuille à surveiller,
-- (4) tableau de bord recalculé sur le système actuel (portefeuilles) au lieu des anciennes tables de paiement.
-- Ré-exécutable sans risque. Aucun impact sur les soldes.

begin;

-- ---------- 1) Porte KYC sur la demande de boutique professionnelle ----------
create or replace function public.require_submitted_kyc_for_shop_request_v69()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_status text;
begin
  if coalesce(current_setting('haitiket.system', true), '') = '1' then return new; end if;
  if coalesce(new.is_official, false) or coalesce(new.kind, 'pro') in ('platform', 'personal', 'official') then return new; end if;
  if char_length(btrim(coalesce(new.name, ''))) < 2 then raise exception 'shop_name_length_invalid'; end if;
  if char_length(btrim(coalesce(new.city, ''))) < 2 then raise exception 'shop_city_required'; end if;
  select iv.status into v_status
    from public.identity_verifications iv
   where iv.user_id = new.owner_id
   order by iv.created_at desc limit 1;
  if v_status is null or v_status not in ('pending', 'approved') then
    raise exception 'kyc_required_before_shop_request';
  end if;
  return new;
end;
$$;
revoke all on function public.require_submitted_kyc_for_shop_request_v69() from public, anon, authenticated;
drop trigger if exists shops_require_submitted_kyc_v69 on public.shops;
create trigger shops_require_submitted_kyc_v69 before insert on public.shops
  for each row execute function public.require_submitted_kyc_for_shop_request_v69();

-- ---------- 2) File des boutiques pour l'administration (propriétaire + KYC) ----------
create or replace function public.admin_shop_requests_v69()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(t) order by t.pending_first desc, t.created_at desc)
    from (
      select s.id, s.name, s.city, s.status, s.verified_at, s.deletion_requested_at, s.deletion_scheduled_at,
             s.deletion_review_status, s.created_at, s.owner_id,
             (s.status = 'pending') as pending_first,
             coalesce(nullif(btrim(p.display_name), ''), 'Nom non renseigné') as owner_name,
             p.phone as owner_phone,
             coalesce((select iv.status from public.identity_verifications iv
                        where iv.user_id = s.owner_id order by iv.created_at desc limit 1), 'none') as kyc_status
        from public.shops s
        left join public.profiles p on p.id = s.owner_id
       where coalesce(s.kind, 'pro') = 'pro' and not coalesce(s.is_official, false)
       order by (s.status = 'pending') desc, s.created_at desc
       limit 150
    ) t
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.admin_shop_requests_v69() from public, anon;
grant execute on function public.admin_shop_requests_v69() to authenticated;

-- ---------- 3) Transactions portefeuille à surveiller (remplace la liste des anciens paiements) ----------
create or replace function public.admin_wallet_transactions_v69(p_all boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(t) order by t.created_at desc)
    from (
      select w.id, w.reference, w.kind, w.status, w.amount_minor, w.fee_minor, w.currency, w.provider, w.created_at,
             coalesce(nullif(btrim(p.display_name), ''), 'Utilisateur') as user_name
        from public.wallet_transactions w
        left join public.profiles p on p.id = w.user_id
       where p_all or w.status in ('pending', 'processing', 'review', 'failed')
       order by w.created_at desc
       limit 100
    ) t
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.admin_wallet_transactions_v69(boolean) from public, anon;
grant execute on function public.admin_wallet_transactions_v69(boolean) to authenticated;

-- ---------- 4) Tableau de bord : chiffres du système portefeuille ----------
create or replace function public.admin_dashboard() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return json_build_object(
    'orders_total', (select count(*) from public.orders),
    'orders_pending_payment', (select count(*) from public.orders where status = 'PENDING_PAYMENT'),
    'orders_paid', (select count(*) from public.orders where status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')),
    'orders_delivered', (select count(*) from public.orders where status in ('DELIVERED','COMPLETED')),
    'orders_cancelled', (select count(*) from public.orders where status in ('CANCELLED','REFUNDED')),
    'gmv_minor', coalesce((select sum(total_minor) from public.orders where currency = 'HTG' and status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')), 0)::bigint,
    'gmv_usd_minor', coalesce((select sum(total_minor) from public.orders where currency = 'USD' and status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')), 0)::bigint,
    'commission_minor', coalesce((select sum(amount_minor) from public.platform_financial_entries where kind = 'commission' and currency = 'HTG'), 0)::bigint,
    'commission_usd_minor', coalesce((select sum(amount_minor) from public.platform_financial_entries where kind = 'commission' and currency = 'USD'), 0)::bigint,
    'fees_minor', coalesce((select sum(amount_minor) from public.wallet_transactions where kind = 'subscription_fee' and status = 'successful' and currency = 'HTG'), 0)::bigint,
    'fees_usd_minor', coalesce((select sum(amount_minor) from public.wallet_transactions where kind = 'subscription_fee' and status = 'successful' and currency = 'USD'), 0)::bigint,
    'payments_pending', (select count(*) from public.wallet_transactions where status in ('pending','processing')),
    'payments_failed', (select count(*) from public.wallet_transactions where status = 'failed'),
    'payments_refund_required', (select count(*) from public.wallet_transactions where status = 'review'),
    'topups_pending', (select count(*) from public.wallet_transactions where kind = 'topup' and status in ('pending','processing')),
    'withdrawals_pending', (select count(*) from public.wallet_transactions where kind = 'withdrawal' and status in ('pending','processing','review')),
    'refunds_to_execute', (select count(*) from public.refund_requests where status = 'to_execute'),
    'shops_active', (select count(*) from public.shops where status = 'active' and kind = 'pro'),
    'shops_pending', (select count(*) from public.shops where status = 'pending'),
    'shop_deletions_pending', (select count(*) from public.shops where deletion_review_status = 'pending_admin'),
    'kyc_pending', (select count(*) from public.identity_verifications where status in ('pending','needs_changes')),
    'bazar_active', (select count(*) from public.products where source = 'bazar' and status = 'published' and paid_until > now()),
    'couriers_approved', (select count(*) from public.courier_applications where status = 'approved'),
    'couriers_available', (select count(*) from public.courier_status where available),
    'jobs_open', (select count(*) from public.delivery_jobs where status = 'open'),
    'jobs_active', (select count(*) from public.delivery_jobs where status in ('assigned','picked_up')),
    'tickets_open', (select count(*) from public.support_tickets where status in ('OPEN','ASSIGNED')),
    'disputes_open', (select count(*) from public.order_disputes where status = 'open'),
    'reports_open', (select count(*) from public.reports where status = 'open'),
    'users_total', (select count(*) from public.profiles));
end $$;
grant execute on function public.admin_dashboard() to authenticated;

commit;

notify pgrst, 'reload schema';
