import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const BASE="https://plopplop.solutionip.app/";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const hex=(b:ArrayBuffer)=>Array.from(new Uint8Array(b)).map(x=>x.toString(16).padStart(2,"0")).join("");
async function hmac(secret:string,body:string){const k=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);return hex(await crypto.subtle.sign("HMAC",k,new TextEncoder().encode(body)));}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 try{
  const url=Deno.env.get("https://ntroqvxeotifsmdzrwyo.supabase.co")!, service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, anon=Deno.env.get("SUPABASE_ANON_KEY")!;
  const userClient=createClient(url,anon,{global:{headers:{Authorization:req.headers.get("Authorization")??""}}});
  const {data:{user}}=await userClient.auth.getUser(); if(!user)return json({error:"Connexion requise"},401);
  const admin=createClient(url,service); const b=await req.json(); const action=String(b.action??"");
  const clientId=Deno.env.get("pp_f9f1d87a0ef26b97f01398319c67")!;
  if(!clientId||!Deno.env.get("63e7a773db6f168686c5f4482946c9a0a082d1367137e3b6634590237e75453a"))return json({error:"Plop Plop non configuré côté serveur"},503);
  if(action==="topup"){
    const amount=Math.round(Number(b.amount_minor)); const currency=String(b.currency??"HTG"); const method=String(b.method??"");
    if(!Number.isSafeInteger(amount)||amount<2000||amount>50000000)return json({error:"Montant invalide (minimum 20 HTG équivalent)"},400);
    if(currency!=="HTG")return json({error:"La recharge du portefeuille est actuellement disponible en HTG seulement"},400);
    if(!["moncash","moncash_ussd","natcash","natcash_ussd"].includes(method))return json({error:"Méthode non prise en charge"},400);
    const reference=`HTK-${crypto.randomUUID().toUpperCase()}`;
    const {data:tid,error:dbErr}=await userClient.rpc("create_wallet_topup",{p_amount_minor:amount,p_currency:currency,p_reference:reference});
    if(dbErr) return json({error:dbErr.message},400);
    const phone=String(b.phone??""); if(method.endsWith("_ussd")&&!/^509\d{8}$/.test(phone))return json({error:"Numéro 509XXXXXXXX requis pour USSD"},400);
    const payload:any={client_id:clientId,refference_id:reference,montant:amount/100,payment_method:method}; if(method.endsWith("_ussd"))payload.phone_number=phone;
    const r=await fetch(new URL("api/paiement-marchand",BASE),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(payload)});
    const d=await r.json().catch(()=>({}));
    if(!r.ok||d.status!==true||!d.transaction_id){await admin.from("wallet_transactions").update({status:"failed",metadata:{provider_error:d}}).eq("id",tid);return json({error:"Plop Plop n'a pas créé la transaction",detail:d.message??null},502);}
    await admin.from("wallet_transactions").update({status:"pending",provider_transaction_id:String(d.transaction_id),metadata:{method,provider_message:d.message??null}}).eq("id",tid);
    return json({reference,transaction_id:String(d.transaction_id),redirect_url:d.url??null,status:"pending",message:method.endsWith("_ussd")?"Confirmez la demande USSD sur votre téléphone.":"Ouvrez l'URL de paiement pour terminer la recharge."});
  }
  if(action==="check_topup"){
    const reference=String(b.reference??"");
    const {data:t,error}=await userClient.from("wallet_transactions").select("reference,amount_minor,currency,status,provider_transaction_id,user_id").eq("reference",reference).eq("user_id",user.id).eq("kind","topup").maybeSingle();
    if(error||!t)return json({error:"Recharge introuvable"},404); if(t.status==="successful")return json({status:"successful"});
    const r=await fetch(new URL("api/paiement-verify",BASE),{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({client_id:clientId,refference_id:reference})});
    const d=await r.json().catch(()=>({})); if(!r.ok||d.status!==true)return json({error:"Vérification fournisseur indisponible",status:t.status},502);
    if(d.trans_status==="ok"){
      const amt=Math.round(Number(d.montant)*100); if(amt!==Number(t.amount_minor))return json({error:"Montant confirmé différent : contrôle manuel requis"},409);
      const {error:creditErr}=await admin.rpc("confirm_wallet_topup",{p_reference:reference,p_provider_transaction_id:String(d.transaction_id??t.provider_transaction_id),p_provider_amount_minor:amt});
      if(creditErr)return json({error:creditErr.message},409); return json({status:"successful"});
    }
    if(["failed","no"].includes(String(d.trans_status)))return json({status:d.trans_status==="failed"?"failed":"pending"});
    return json({status:"pending"});
  }
  return json({error:"Action inconnue"},400);
 }catch(e){return json({error:String((e as Error).message??e)},500);}
});
