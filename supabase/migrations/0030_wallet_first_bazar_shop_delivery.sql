-- HAITIKET V20 — frais Bazar, abonnement boutique et choix du prix de livraison
-- Les transactions internes sont débitées/créditées par RPC serveur, jamais par le client.

create or replace function public._wallet_balance_minor(p_account uuid) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(sum(case when status='successful' then
    case when kind in ('withdrawal','purchase','subscription_fee') then -amount_minor-fee_minor
         else amount_minor-fee_minor end else 0 end),0)::bigint
  from public.wallet_transactions where account_id=p_account
$$;
revoke all on function public._wallet_balance_minor(uuid) from public,anon,authenticated;

create or replace function public.quote_wallet_fee_usd(p_kind text) returns numeric
language plpgsql stable security definer set search_path=public as $$
declare v_key text; v numeric;
begin
  v_key := case p_kind when 'bazar_listing' then 'bazar_fee_usd'
                       when 'shop_plan' then 'shop_fee_usd'
                       when 'shop_plan_yearly' then 'shop_fee_yearly_usd'
                       else null end;
  if v_key is null then raise exception 'Type de frais inconnu'; end if;
  select value::numeric into v from public.platform_settings where key=v_key;
  if v is null or v<=0 then return null; end if;
  return round(v,2);
end $$;
revoke all on function public.quote_wallet_fee_usd(text) from public;
grant execute on function public.quote_wallet_fee_usd(text) to authenticated;

create or replace function public.pay_bazar_listing_from_wallet(p_product uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); p public.products; sh public.shops; fee numeric; amt bigint; aid uuid; bal bigint; ref text;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  select * into p from public.products where id=p_product for update;
  if p.id is null or p.source<>'bazar' then raise exception 'Annonce Bazar introuvable'; end if;
  select * into sh from public.shops where id=p.shop_id and owner_id=uid for share;
  if sh.id is null then raise exception 'Cette annonce ne vous appartient pas'; end if;
  if p.status in ('blocked','removed') then raise exception 'Annonce bloquée ou supprimée'; end if;
  if p.paid_until is not null and p.paid_until>now() then raise exception 'Cette annonce est déjà payée jusqu’au '||to_char(p.paid_until,'YYYY-MM-DD'); end if;
  select value::numeric into fee from public.platform_settings where key='bazar_fee_usd';
  if fee is null or fee<=0 then raise exception 'Frais Bazar non configurés'; end if;
  amt:=round(fee*100)::bigint;
  insert into public.wallet_accounts(user_id,currency) values(uid,'USD') on conflict(user_id,currency) do nothing;
  select id into aid from public.wallet_accounts where user_id=uid and currency='USD' for update;
  bal:=public._wallet_balance_minor(aid);
  if bal<amt then raise exception 'Solde USD insuffisant : disponible %, requis % centimes',bal,amt; end if;
  ref:='BAZAR_LISTING:'||p.id::text||':'||coalesce(to_char(p.paid_until,'YYYYMMDDHH24MISSUS'),'never');
  insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
  values(aid,uid,ref,'purchase','successful',amt,'USD','internal',jsonb_build_object('purpose','bazar_listing','product_id',p.id,'shop_id',p.shop_id,'duration_days',14));
  perform set_config('haitiket.system','1',true);
  update public.products set status='published',paid_until=greatest(coalesce(paid_until,now()),now())+interval '14 days' where id=p.id;
  return jsonb_build_object('success',true,'currency','USD','amount_minor',amt,'paid_until',greatest(coalesce(p.paid_until,now()),now())+interval '14 days');
end $$;
revoke all on function public.pay_bazar_listing_from_wallet(uuid) from public,anon;
grant execute on function public.pay_bazar_listing_from_wallet(uuid) to authenticated;

create or replace function public.pay_shop_plan_from_wallet(p_shop uuid,p_period text default 'monthly') returns jsonb
language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); sh public.shops; fee numeric; amt bigint; aid uuid; bal bigint; setting_key text; duration interval; ref text;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  if p_period not in ('monthly','yearly') then raise exception 'Période d’abonnement invalide'; end if;
  select * into sh from public.shops where id=p_shop and owner_id=uid and kind='pro' for update;
  if sh.id is null then raise exception 'Boutique professionnelle introuvable'; end if;
  if sh.plan_paid_until is not null and sh.plan_paid_until>now() then raise exception 'Abonnement déjà actif jusqu’au '||to_char(sh.plan_paid_until,'YYYY-MM-DD'); end if;
  setting_key:=case when p_period='yearly' then 'shop_fee_yearly_usd' else 'shop_fee_usd' end;
  select value::numeric into fee from public.platform_settings where key=setting_key;
  if fee is null or fee<=0 then raise exception 'Tarif de l’abonnement non configuré'; end if;
  amt:=round(fee*100)::bigint;
  duration:=case when p_period='yearly' then interval '1 year' else interval '30 days' end;
  insert into public.wallet_accounts(user_id,currency) values(uid,'USD') on conflict(user_id,currency) do nothing;
  select id into aid from public.wallet_accounts where user_id=uid and currency='USD' for update;
  bal:=public._wallet_balance_minor(aid);
  if bal<amt then raise exception 'Solde USD insuffisant : disponible %, requis % centimes',bal,amt; end if;
  ref:='SHOP_PLAN:'||sh.id::text||':'||coalesce(to_char(sh.plan_paid_until,'YYYYMMDDHH24MISSUS'),'never');
  insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
  values(aid,uid,ref,'subscription_fee','successful',amt,'USD','internal',jsonb_build_object('purpose','shop_plan','shop_id',sh.id,'period',p_period));
  update public.shops set plan_paid_until=greatest(coalesce(plan_paid_until,now()),now())+duration where id=sh.id;
  return jsonb_build_object('success',true,'currency','USD','amount_minor',amt,'period',p_period);
end $$;
revoke all on function public.pay_shop_plan_from_wallet(uuid,text) from public,anon;
grant execute on function public.pay_shop_plan_from_wallet(uuid,text) to authenticated;

-- Sélection de l'offre + ajustement du coût dans une seule transaction.
-- Une offre plus chère débite le portefeuille de la devise de la commande.
-- Une offre moins chère crédite le remboursement dans ce même portefeuille.
create or replace function public.select_delivery_price_offer(p_offer uuid) returns void
language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); f public.delivery_job_offers; j public.delivery_jobs; o public.orders; aid uuid; bal bigint; delta bigint; ref text;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  select * into f from public.delivery_job_offers where id=p_offer for update;
  if f.id is null then raise exception 'Offre introuvable'; end if;
  select * into j from public.delivery_jobs where id=f.job_id for update;
  if j.id is null or j.status<>'open' then raise exception 'La mission a déjà été attribuée ou fermée'; end if;
  select * into o from public.orders where id=j.order_id and customer_id=uid and delivery_mode='delivery' for update;
  if o.id is null then raise exception 'Seul le client de la commande peut choisir le prix'; end if;
  if o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') then raise exception 'Commande non éligible à la sélection d’un coursier'; end if;
  if f.status<>'pending' or f.expires_at<=now() then raise exception 'Cette offre a expiré'; end if;
  if f.currency<>o.currency or j.currency<>o.currency then raise exception 'La devise de l’offre ne correspond pas à la commande'; end if;
  if not exists(select 1 from public.courier_status cs where cs.user_id=f.courier_id and cs.available=true and cs.location_updated_at>now()-interval '3 minutes') then
    raise exception 'Le coursier n’est plus disponible ou sa position est trop ancienne';
  end if;
  delta:=f.amount_minor-o.delivery_minor;
  if delta>0 then
    insert into public.wallet_accounts(user_id,currency) values(uid,o.currency) on conflict(user_id,currency) do nothing;
    select id into aid from public.wallet_accounts where user_id=uid and currency=o.currency for update;
    bal:=public._wallet_balance_minor(aid);
    if bal<delta then raise exception 'Solde % insuffisant pour le supplément : disponible %, requis % centimes',o.currency,bal,delta; end if;
    ref:='DELIVERY_OFFER:'||o.id::text;
    insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
    values(aid,uid,ref,'purchase','successful',delta,o.currency,'internal',jsonb_build_object('purpose','delivery_fee','order_id',o.id,'offer_id',f.id,'courier_id',f.courier_id));
  elsif delta<0 then
    insert into public.wallet_accounts(user_id,currency) values(uid,o.currency) on conflict(user_id,currency) do nothing;
    select id into aid from public.wallet_accounts where user_id=uid and currency=o.currency for update;
    ref:='DELIVERY_REFUND:'||o.id::text;
    insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
    values(aid,uid,ref,'refund','successful',abs(delta),o.currency,'internal',jsonb_build_object('purpose','delivery_fee_adjustment','order_id',o.id,'offer_id',f.id));
  end if;
  update public.orders set delivery_minor=f.amount_minor,total_minor=total_minor+delta where id=o.id;
  update public.delivery_jobs set status='assigned',courier_id=f.courier_id,assigned_at=now(),pay_minor=f.amount_minor,currency=f.currency where id=j.id and status='open';
  if not found then raise exception 'La mission a été attribuée simultanément à un autre coursier'; end if;
  update public.delivery_job_offers set status='selected',updated_at=now() where id=f.id;
  update public.delivery_job_offers set status='rejected',updated_at=now() where job_id=j.id and id<>f.id and status='pending';
end $$;
revoke all on function public.select_delivery_price_offer(uuid) from public,anon;
grant execute on function public.select_delivery_price_offer(uuid) to authenticated;

comment on function public.pay_bazar_listing_from_wallet(uuid) is 'Débite le portefeuille USD pour publier une annonce Bazar pendant 14 jours.';
comment on function public.pay_shop_plan_from_wallet(uuid,text) is 'Débite le portefeuille USD pour un abonnement boutique mensuel ou annuel.';
comment on function public.select_delivery_price_offer(uuid) is 'Sélectionne une offre de livraison et ajuste le coût via le portefeuille interne dans la même transaction.';
