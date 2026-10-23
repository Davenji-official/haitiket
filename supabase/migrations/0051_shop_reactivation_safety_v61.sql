-- V61: rejected shop-deletion requests must not silently reactivate a shop.
-- Reopening is a separate, explicit seller action and requires approved KYC and resolved refunds.
create or replace function public.keep_rejected_shop_suspended_v61()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.deletion_review_status='rejected' and old.deletion_review_status is distinct from 'rejected' then
    new.status:='suspended';
  end if;
  return new;
end $$;
revoke all on function public.keep_rejected_shop_suspended_v61() from public,anon,authenticated;
drop trigger if exists keep_rejected_shop_suspended_v61 on public.shops;
create trigger keep_rejected_shop_suspended_v61 before update of deletion_review_status,status on public.shops
for each row execute function public.keep_rejected_shop_suspended_v61();

create or replace function public.seller_reactivate_shop_v61(p_shop uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.shops%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into s from public.shops where id=p_shop and owner_id=auth.uid() for update;
  if not found then raise exception 'shop_not_found_or_not_owned'; end if;
  if s.kind='platform' or coalesce(s.is_official,false) then raise exception 'official_shop_managed_by_admin'; end if;
  if s.status<>'suspended' or s.deletion_review_status<>'rejected' then
    raise exception 'shop_must_have_rejected_deletion_request';
  end if;
  if not exists(select 1 from public.identity_verifications iv where iv.user_id=auth.uid() and iv.status='approved') then
    raise exception 'approved_kyc_required_before_shop_reactivation';
  end if;
  if exists(select 1 from public.orders o join public.refund_requests r on r.order_id=o.id
      where o.shop_id=p_shop and r.status<>'executed') then
    raise exception 'shop_has_unresolved_refunds';
  end if;
  update public.shops set status='active',deletion_review_status='none',deletion_requested_at=null,
    deletion_scheduled_at=null,deletion_reviewed_by=null,deletion_reviewed_at=null
    where id=p_shop returning * into s;
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
    values(auth.uid(),'seller_shop_reactivated','shop',p_shop,'Demande de suppression refusée; réactivation explicite après contrôles');
  return jsonb_build_object('shop_id',s.id,'status',s.status,'message','Boutique réactivée après vérification KYC et des remboursements.');
end $$;
revoke all on function public.seller_reactivate_shop_v61(uuid) from public,anon;
grant execute on function public.seller_reactivate_shop_v61(uuid) to authenticated;

comment on function public.seller_reactivate_shop_v61(uuid) is
'Réactivation explicite après refus administratif de suppression, KYC approuvé et absence de remboursements non résolus.';
