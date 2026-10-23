-- HAITIKET V18 : paiement du supplément de livraison après choix d'une offre.
-- Le montant déjà facturé pour la livraison est déduit : pas de double facturation.
-- La confirmation du prestataire reste obligatoire; aucun paiement n'est simulé.

alter table public.payment_attempts drop constraint if exists payment_attempts_purpose_check;
alter table public.payment_attempts add constraint payment_attempts_purpose_check
  check (purpose in ('order','bazar_listing','shop_plan','delivery_fee'));

create or replace function public.delivery_fee_due(p_order uuid)
returns bigint
language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); o public.orders; j public.delivery_jobs;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  select * into o from public.orders where id=p_order and customer_id=uid for share;
  if o.id is null then raise exception 'Commande introuvable ou accès refusé'; end if;
  select * into j from public.delivery_jobs where order_id=p_order and status='assigned' for share;
  if j.id is null then raise exception 'Choisissez d’abord une offre de coursier'; end if;
  if j.currency <> o.currency then raise exception 'La devise de livraison ne correspond pas à la commande'; end if;
  if o.currency <> 'HTG' then raise exception 'Le paiement du supplément de livraison est actuellement disponible uniquement en HTG'; end if;
  return greatest(0,j.pay_minor-o.delivery_minor);
end $$;
revoke all on function public.delivery_fee_due(uuid) from public,anon;
grant execute on function public.delivery_fee_due(uuid) to authenticated;

-- Remplacement de start_payment : le nouveau type ne peut payer que le supplément
-- de l'offre choisie par le propriétaire de la commande.
create or replace function public.start_payment(p_purpose text,p_target uuid,p_user uuid)
returns public.payment_attempts
language plpgsql security definer set search_path=public as $$
declare a public.payment_attempts; amt bigint; o public.orders; pr public.products; sh public.shops; j public.delivery_jobs;
begin
  if p_user is null then raise exception 'Utilisateur requis'; end if;
  if p_purpose='order' then
    select * into o from public.orders where id=p_target and customer_id=p_user for update;
    if o.id is null then raise exception 'Commande introuvable'; end if;
    if o.status not in ('PENDING_PAYMENT','PAYMENT_PROCESSING') then raise exception 'Commande non payable (statut %) ',o.status; end if;
    if o.reserved_until is not null and o.reserved_until<now() then raise exception 'Réservation expirée : veuillez recommander'; end if;
    if o.currency<>'HTG' then raise exception 'Seul le HTG est pris en charge'; end if;
    amt:=o.total_minor;
    update public.orders set reserved_until=greatest(coalesce(reserved_until,now()),now()+interval '25 minutes') where id=o.id;
  elsif p_purpose='delivery_fee' then
    select * into o from public.orders where id=p_target and customer_id=p_user for update;
    if o.id is null then raise exception 'Commande introuvable'; end if;
    if o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') then raise exception 'Commande non éligible au paiement de livraison'; end if;
    if o.currency<>'HTG' then raise exception 'Le supplément de livraison est actuellement disponible uniquement en HTG'; end if;
    select * into j from public.delivery_jobs where order_id=o.id and status='assigned' for update;
    if j.id is null then raise exception 'Aucune offre de coursier sélectionnée'; end if;
    if j.currency<>o.currency then raise exception 'Devise incohérente'; end if;
    amt:=j.pay_minor-o.delivery_minor;
    if amt<=0 then raise exception 'Aucun supplément à payer : les frais déjà réglés couvrent cette offre'; end if;
    if exists(select 1 from public.payment_attempts where purpose='delivery_fee' and target_id=o.id and user_id=p_user and status='successful') then
      raise exception 'Le supplément de livraison est déjà payé';
    end if;
  elsif p_purpose='bazar_listing' then
    select p.* into pr from public.products p join public.shops s on s.id=p.shop_id where p.id=p_target and p.source='bazar' and s.owner_id=p_user;
    if pr.id is null then raise exception 'Annonce introuvable'; end if;
    if pr.status in ('blocked','removed') then raise exception 'Annonce bloquée'; end if;
    amt:=public._fee_minor('bazar_fee_usd');
  elsif p_purpose='shop_plan' then
    select * into sh from public.shops where id=p_target and owner_id=p_user and kind='pro';
    if sh.id is null then raise exception 'Boutique introuvable'; end if;
    amt:=public._fee_minor('shop_fee_usd');
  else raise exception 'Type de paiement invalide'; end if;
  if amt is null or amt<=0 then raise exception 'Montant invalide'; end if;
  if amt>7500000 then raise exception 'Montant supérieur à 75 000 HTG : paiement impossible'; end if;
  update public.payment_attempts set status='cancelled',updated_at=now()
    where purpose=p_purpose and target_id=p_target and user_id=p_user and status='created';
  insert into public.payment_attempts(purpose,target_id,order_id,user_id,amount_minor,currency,provider)
  values(p_purpose,p_target,case when p_purpose in ('order','delivery_fee') then p_target end,p_user,amt,'HTG','bazik') returning * into a;
  return a;
end $$;
revoke all on function public.start_payment(text,uuid,uuid) from public,anon,authenticated;

-- Préserve les règles financières des fonctions précédentes et ajoute un cas dédié
-- qui crédite le registre du coursier uniquement après confirmation fournisseur.
create or replace function public.apply_payment_success(p_attempt uuid) returns text
language plpgsql security definer set search_path=public as $$
declare a public.payment_attempts; o public.orders; j public.delivery_jobs;
begin
  select * into a from public.payment_attempts where id=p_attempt for update;
  if a.id is null then raise exception 'Tentative introuvable'; end if;
  if a.status='successful' then return 'already'; end if;
  perform set_config('haitiket.system','1',true);
  if a.purpose='delivery_fee' then
    select * into o from public.orders where id=a.order_id for update;
    if o.id is null or o.customer_id<>a.user_id or o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') then
      update public.payment_attempts set status='refund_required',updated_at=now() where id=a.id;
      return 'refund_required';
    end if;
    select * into j from public.delivery_jobs where order_id=o.id and status='assigned' for update;
    if j.id is null or j.currency<>a.currency or j.pay_minor-o.delivery_minor<>a.amount_minor then
      update public.payment_attempts set status='refund_required',updated_at=now() where id=a.id;
      return 'refund_required';
    end if;
    update public.payment_attempts set status='successful',updated_at=now() where id=a.id;
    insert into public.ledger_entries(attempt_id,order_id,kind,amount_minor,currency) values
      (a.id,o.id,'payment_received',a.amount_minor,a.currency),
      (a.id,o.id,'courier_payable',a.amount_minor,a.currency)
    on conflict do nothing;
    return 'delivery_fee_paid';
  elsif a.purpose='order' then
    select * into o from public.orders where id=a.order_id for update;
    if o.status in ('PENDING_PAYMENT','PAYMENT_PROCESSING') then null;
    elsif o.status='CANCELLED' then
      if not public._take_stock(o.id,'reservation_after_late_payment') then
        update public.payment_attempts set status='refund_required',updated_at=now() where id=a.id; return 'refund_required';
      end if;
    else
      update public.payment_attempts set status='refund_required',updated_at=now() where id=a.id; return 'refund_required';
    end if;
    update public.payment_attempts set status='successful',updated_at=now() where id=a.id;
    perform public._set_order_status(o.id,'PAID',null,'payment_confirmed');
    insert into public.ledger_entries(attempt_id,order_id,kind,amount_minor,currency) values
      (a.id,o.id,'payment_received',o.total_minor,o.currency),
      (a.id,o.id,'seller_payable',o.seller_net_minor,o.currency),
      (a.id,o.id,'platform_net',coalesce(o.platform_net_minor,o.commission_minor-o.discount_minor),o.currency),
      (a.id,o.id,'courier_payable',o.delivery_minor,o.currency) on conflict do nothing;
    return 'paid';
  elsif a.purpose='bazar_listing' then
    update public.products set status='published',paid_until=greatest(coalesce(paid_until,now()),now())+interval '14 days'
      where id=a.target_id and status in ('draft','paused','published');
    update public.payment_attempts set status='successful',updated_at=now() where id=a.id;
    insert into public.ledger_entries(attempt_id,kind,amount_minor,currency) values(a.id,'bazar_fee',a.amount_minor,a.currency) on conflict do nothing;
    return 'paid';
  elsif a.purpose='shop_plan' then
    update public.shops set plan_paid_until=greatest(coalesce(plan_paid_until,now()),now())+interval '30 days' where id=a.target_id;
    update public.payment_attempts set status='successful',updated_at=now() where id=a.id;
    insert into public.ledger_entries(attempt_id,kind,amount_minor,currency) values(a.id,'shop_plan_fee',a.amount_minor,a.currency) on conflict do nothing;
    return 'paid';
  end if;
  raise exception 'Type de paiement non pris en charge';
end $$;
revoke all on function public.apply_payment_success(uuid) from public,anon,authenticated;

-- Ne laisse pas le coursier collecter tant que le supplément exigible n'est pas payé.
create or replace function public.confirm_pickup(p_job uuid,p_pin text) returns boolean
language plpgsql security definer set search_path=public as $$
declare j public.delivery_jobs; o public.orders;
begin
  select * into j from public.delivery_jobs where id=p_job and courier_id=auth.uid() for update;
  if j.id is null then raise exception 'Mission introuvable'; end if;
  if j.status<>'assigned' then raise exception 'Collecte non attendue'; end if;
  if j.failed>=5 then raise exception 'Trop de tentatives : contactez le support'; end if;
  select * into o from public.orders where id=j.order_id for update;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if j.pay_minor>o.delivery_minor and not exists(
    select 1 from public.payment_attempts a where a.order_id=o.id and a.purpose='delivery_fee' and a.status='successful'
  ) then raise exception 'Supplément de livraison non payé : attendez la confirmation du paiement'; end if;
  if j.pickup_pin=trim(p_pin) then
    update public.delivery_jobs set status='picked_up',failed=0 where id=p_job;
    perform public._set_order_status(j.order_id,'IN_TRANSIT',auth.uid(),'pickup_confirmed');
    return true;
  end if;
  update public.delivery_jobs set failed=failed+1 where id=p_job;
  return false;
end $$;
grant execute on function public.confirm_pickup(uuid,text) to authenticated;
