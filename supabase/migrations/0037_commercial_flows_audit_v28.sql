-- HAITIKET V28 — tarifs commerciaux et audit boutiques/Bazar.
-- Migration additive : aucun débit, crédit ou changement de statut commercial automatique.

-- Le tarif annuel souhaité est configurable par l'administration; valeur initiale uniquement si absente.
insert into public.platform_settings(key,value) values ('shop_fee_yearly_usd','200')
on conflict (key) do nothing;

drop policy if exists settings_public_read on public.platform_settings;
create policy settings_public_read on public.platform_settings for select
using (key in ('commission_bps','reservation_minutes','bazar_fee_usd','shop_fee_usd','shop_fee_yearly_usd'));

-- Autorise l'administration à modifier le tarif annuel, avec la même validation que les autres tarifs USD.
create or replace function public.admin_set_setting(p_key text,p_value text) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_key not in ('commission_bps','reservation_minutes','delivery_flat_minor','usd_htg_rate','usd_htg_topup_rate','usd_htg_withdraw_rate','bazar_fee_usd','shop_fee_usd','shop_fee_yearly_usd','enforce_shop_plan','referral_reward_minor') then
    raise exception 'Réglage inconnu';
  end if;
  if p_key='enforce_shop_plan' then
    if p_value not in ('true','false') then raise exception 'Valeur attendue : true ou false'; end if;
  elsif p_key in ('usd_htg_rate','usd_htg_topup_rate','usd_htg_withdraw_rate','bazar_fee_usd','shop_fee_usd','shop_fee_yearly_usd') then
    if p_value !~ '^[0-9]{1,6}(\.[0-9]{1,4})?$' or p_value::numeric<=0 then raise exception 'Nombre positif requis'; end if;
  else
    if p_value !~ '^[0-9]{1,9}$' then raise exception 'Nombre entier requis'; end if;
  end if;
  insert into public.platform_settings(key,value) values(p_key,trim(p_value))
  on conflict(key) do update set value=excluded.value,updated_at=now();
  insert into public.admin_audit_logs(actor,action,resource,reason)
    values(auth.uid(),'set_setting',p_key,left(p_value,100));
end $$;
revoke all on function public.admin_set_setting(text,text) from public,anon;
grant execute on function public.admin_set_setting(text,text) to authenticated;

create or replace function public.run_commercial_flow_audit_v28()
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  actor_id uuid := auth.uid();
  report jsonb;
  run_id uuid;
  issue_count bigint;
  warning_count bigint;
begin
  if actor_id is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : déverrouillez la console administrateur';
  end if;

  select jsonb_build_object(
    'generated_at',now(),
    'settings',jsonb_build_object(
      'bazar_fee_usd',(select value from public.platform_settings where key='bazar_fee_usd'),
      'shop_fee_monthly_usd',(select value from public.platform_settings where key='shop_fee_usd'),
      'shop_fee_yearly_usd',(select value from public.platform_settings where key='shop_fee_yearly_usd'),
      'enforce_shop_plan',(select value from public.platform_settings where key='enforce_shop_plan')
    ),
    'bazar',jsonb_build_object(
      'published_active',(select count(*) from public.products where source='bazar' and status='published' and paid_until>now()),
      'published_expired',(select count(*) from public.products where source='bazar' and status='published' and (paid_until is null or paid_until<=now())),
      'published_missing_expiry',(select count(*) from public.products where source='bazar' and status='published' and paid_until is null),
      'expired_pending_removal',(select count(*) from public.products where source='bazar' and status in ('published','paused','draft') and paid_until<now()-interval '30 days')
    ),
    'shops',jsonb_build_object(
      'professional_total',(select count(*) from public.shops where kind='pro'),
      'professional_active_plan',(select count(*) from public.shops where kind='pro' and plan_paid_until>now()),
      'professional_expired_plan',(select count(*) from public.shops where kind='pro' and (plan_paid_until is null or plan_paid_until<=now())),
      'active_plan_without_matching_wallet_fee',(select count(*) from public.shops s where s.kind='pro' and s.plan_paid_until>now() and not exists (
        select 1 from public.wallet_transactions t where t.user_id=s.owner_id and t.kind='subscription_fee' and t.status='successful' and t.metadata->>'shop_id'=s.id::text and t.metadata->>'purpose'='shop_plan'
      ))
    ),
    'wallet_commercial_transactions',jsonb_build_object(
      'successful_bazar_fees',(select count(*) from public.wallet_transactions where kind='purchase' and status='successful' and metadata->>'purpose'='bazar_listing'),
      'successful_shop_fees',(select count(*) from public.wallet_transactions where kind='subscription_fee' and status='successful' and metadata->>'purpose'='shop_plan'),
      'duplicate_references',(select count(*) from (select reference from public.wallet_transactions where metadata->>'purpose' in ('bazar_listing','shop_plan') group by reference having count(*)>1) d)
    ),
    'mutations_performed',false
  ) into report;

  issue_count :=
    coalesce((report#>>'{bazar,published_expired}')::bigint,0) +
    coalesce((report#>>'{wallet_commercial_transactions,duplicate_references}')::bigint,0) +
    case when coalesce(report#>>'{settings,shop_fee_yearly_usd}','')='' then 1 else 0 end;
  warning_count :=
    coalesce((report#>>'{bazar,expired_pending_removal}')::bigint,0) +
    coalesce((report#>>'{shops,professional_expired_plan}')::bigint,0) +
    coalesce((report#>>'{shops,active_plan_without_matching_wallet_fee}')::bigint,0);

  insert into public.finance_audit_runs(actor,summary,status)
    values(actor_id,report||jsonb_build_object('issue_count',issue_count,'warning_count',warning_count),
      case when issue_count=0 and warning_count=0 then 'clean' else 'issues_found' end)
    returning id into run_id;
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
    values(actor_id,'commercial_flow_audit_v28','commercial_audit',run_id,
      'read-only; issue_count='||issue_count::text||'; warning_count='||warning_count::text);
  return report||jsonb_build_object('audit_run_id',run_id,'issue_count',issue_count,'warning_count',warning_count,
    'status',case when issue_count=0 and warning_count=0 then 'clean' else 'issues_found' end);
end $$;
revoke all on function public.run_commercial_flow_audit_v28() from public,anon;
grant execute on function public.run_commercial_flow_audit_v28() to authenticated;
comment on function public.run_commercial_flow_audit_v28() is 'Audit commercial en lecture seule : tarifs, annonces Bazar, abonnements et transactions internes.';
