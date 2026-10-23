-- HAITIKET V22 — remboursement interne idempotent vers le portefeuille du client.
-- N'exécute PAS de remboursement externe Plop Plop. Réservé à un administrateur déverrouillé.

create or replace function public.admin_execute_wallet_refund(p_id uuid, p_note text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.refund_requests;
  o public.orders;
  purchase_tx public.wallet_transactions;
  aid uuid;
  credited bigint := 0;
  note_text text := left(trim(coalesce(p_note,'')),300);
begin
  if auth.uid() is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : déverrouillez la console administrateur';
  end if;
  if length(note_text) < 5 then raise exception 'Une justification de 5 caractères minimum est requise'; end if;

  select * into r from public.refund_requests where id=p_id for update;
  if r.id is null then raise exception 'Demande de remboursement introuvable'; end if;
  if r.status <> 'to_execute' then raise exception 'Cette demande a déjà été traitée'; end if;

  select * into o from public.orders where id=r.order_id for update;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if r.user_id <> o.customer_id then raise exception 'Le bénéficiaire ne correspond pas au client de la commande'; end if;
  if r.amount_minor <> o.total_minor then raise exception 'Montant de remboursement différent du total de commande : revue manuelle requise'; end if;
  if o.status = 'REFUNDED' then raise exception 'La commande est déjà remboursée'; end if;
  if exists(select 1 from public.order_disputes d where d.order_id=o.id and d.status='open') then
    raise exception 'Remboursement bloqué : un litige est encore ouvert';
  end if;

  select * into purchase_tx from public.wallet_transactions
   where reference='ORDER:'||o.id::text and user_id=o.customer_id
     and kind='purchase' and status='successful'
     and amount_minor=o.total_minor and currency=o.currency
   for update;
  if purchase_tx.id is null then
    raise exception 'Aucun débit de portefeuille interne correspondant. Utilisez le processus de remboursement externe ou une revue manuelle.';
  end if;

  -- Ne jamais créditer le client tout en laissant des gains déjà dépensables chez vendeur/coursier.
  if exists(select 1 from public.wallet_transactions t
      where t.reference in ('SELLER_ORDER:'||o.id::text,'COURIER_ORDER:'||o.id::text)
        and t.status='successful' and t.kind in ('seller_credit','courier_credit')) then
    raise exception 'Un revenu vendeur/coursier est déjà libéré : revue financière manuelle obligatoire';
  end if;
  if exists(select 1 from public.wallet_transactions where reference='ORDER_REFUND:'||o.id::text) then
    raise exception 'Un remboursement interne existe déjà';
  end if;

  insert into public.wallet_accounts(user_id,currency)
    values(o.customer_id,o.currency) on conflict(user_id,currency) do nothing;
  select id into aid from public.wallet_accounts where user_id=o.customer_id and currency=o.currency for update;

  insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
  values(aid,o.customer_id,'ORDER_REFUND:'||o.id::text,'refund','successful',o.total_minor,o.currency,'internal',
    jsonb_build_object('order_id',o.id,'refund_request_id',r.id,'source','wallet_order_refund_v22','admin_note',note_text));
  get diagnostics credited = row_count;

  update public.wallet_transactions set status='reversed',updated_at=now(),
    metadata=metadata||jsonb_build_object('reversed_for_refund',r.id,'admin_note',note_text)
   where reference in ('SELLER_ORDER:'||o.id::text,'COURIER_ORDER:'||o.id::text)
     and status='pending' and kind in ('seller_credit','courier_credit');

  update public.refund_requests set status='executed',executed_at=now(),note=note_text where id=r.id;
  perform public._set_order_status(o.id,'REFUNDED',auth.uid(),'wallet_refund_executed');
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
   values(auth.uid(),'wallet_refund_executed','refund',r.id,'order='||o.id::text||'; amount_minor='||o.total_minor::text||'; currency='||o.currency||'; '||note_text);
  perform public._notify(r.user_id,'order','Remboursement crédité dans votre portefeuille',null,o.id);

  return jsonb_build_object('success',true,'refund_request_id',r.id,'order_id',o.id,
    'amount_minor',o.total_minor,'currency',o.currency,'credited_transactions',credited,
    'destination','internal_wallet','status','executed');
end $$;
revoke all on function public.admin_execute_wallet_refund(uuid,text) from public,anon;
grant execute on function public.admin_execute_wallet_refund(uuid,text) to authenticated;
comment on function public.admin_execute_wallet_refund(uuid,text) is
'Rembourse un débit interne vers le portefeuille client, idempotent et audité; refuse les paiements externes et les gains déjà libérés.';
