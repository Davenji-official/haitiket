-- V66: enforce approved KYC for Bazar listings at database level.
-- UI checks improve guidance; this trigger is the authoritative guard.
create or replace function public.require_approved_kyc_for_bazar_v66()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_status text;
begin
  if coalesce(new.source, '') <> 'bazar' then
    return new;
  end if;

  select s.owner_id into v_owner
    from public.shops s
   where s.id = new.shop_id
   limit 1;

  if v_owner is null then
    raise exception 'bazar_shop_owner_not_found' using errcode = '23514';
  end if;

  -- The listing owner must have an approved identity dossier. The owner check prevents
  -- a seller from borrowing another account's KYC status.
  select iv.status into v_status
    from public.identity_verifications iv
   where iv.user_id = v_owner
   order by iv.created_at desc
   limit 1;

  if v_status is distinct from 'approved' then
    raise exception 'bazar_requires_approved_kyc' using errcode = '42501',
      detail = 'Bazar publishing requires an administrator-approved identity verification.';
  end if;

  return new;
end;
$$;

revoke all on function public.require_approved_kyc_for_bazar_v66() from public, anon, authenticated;

drop trigger if exists products_require_approved_kyc_for_bazar_v66 on public.products;
create trigger products_require_approved_kyc_for_bazar_v66
before insert or update of source, shop_id on public.products
for each row execute function public.require_approved_kyc_for_bazar_v66();

comment on function public.require_approved_kyc_for_bazar_v66() is
'V66: blocks Bazar listing creation or ownership/source changes unless the shop owner has administrator-approved KYC.';
