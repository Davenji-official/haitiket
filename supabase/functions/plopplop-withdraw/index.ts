import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const BASE = "https://plopplop.solutionip.app/";
const cors = {"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json = (body: unknown, status=200) => new Response(JSON.stringify(body), {status, headers:{...cors,"Content-Type":"application/json"}});
const hex = (buf:ArrayBuffer) => Array.from(new Uint8Array(buf)).map(v=>v.toString(16).padStart(2,"0")).join("");
async function sign(secret:string, payload:string) { const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]); return hex(await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(payload))); }
async function providerPost(path:string, body:unknown, token?:string) { return await fetch(new URL(path,BASE),{method:"POST",headers:{"Content-Type":"application/json",...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body)}); }
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
 try {
  const url=Deno.env.get("SUPABASE_URL")!, anon=Deno.env.get("SUPABASE_ANON_KEY")!, service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const client=createClient(url,anon,{global:{headers:{Authorization:req.headers.get("Authorization")??""}}});
  const {data:{user}}=await client.auth.getUser(); if(!user) return json({error:"Connexion requise"},401);
  const admin=createClient(url,service); const clientId=Deno.env.get("PLOPPLOP_CLIENT_ID")??""; const secret=Deno.env.get("PLOPPLOP_CLIENT_SECRET")??"";
  if(!clientId||!secret) return json({error:"Plop Plop n'est pas configuré côté serveur"},503);
  const b=await req.json(); const action=String(b.action??"");
  if(action==="withdraw") {
   const amountMinor=Math.round(Number(b.amount_minor)); const phone=String(b.phone??"").trim(); const method=String(b.method??"");
   if(!Number.isSafeInteger(amountMinor)||amountMinor<5000||amountMinor>50000000) return json({error:"Le retrait doit être compris entre 50 et 500 000 HTG."},400);
   if(!/^509\d{8}$/.test(phone)) return json({error:"Numéro haïtien invalide (509XXXXXXXX)."},400);
   if(!["moncash","natcash"].includes(method)) return json({error:"Méthode de retrait non prise en charge."},400);
   const reference=`HTKW-${crypto.randomUUID().toUpperCase()}`;
   const {data:prepared,error:prepError}=await client.rpc("prepare_wallet_withdrawal",{p_amount_minor:amountMinor,p_currency:"HTG",p_phone:phone,p_reference:reference});
   if(prepError) return json({error:prepError.message},400);
   // Plop Plop withdraws from the merchant's prepaid float, not from a personal wallet.
   // HAITIKET therefore needs a separately funded merchant float and reconciliation.
   const authRes=await providerPost("api/auth/marchand",{client_id:clientId,client_secret:secret}); const authData=await authRes.json().catch(()=>({}));
   if(!authRes.ok||authData.success!==true||!authData.token){ await admin.rpc("finish_wallet_withdrawal",{p_reference:reference,p_success:false,p_provider_transaction_id:null,p_fee_minor:0}); return json({error:"Authentification marchand Plop Plop échouée. Le retrait n'a pas été envoyé."},502); }
   const timestamp=Math.floor(Date.now()/1000); const amount=(amountMinor/100).toFixed(2); const payload=[amount,method,phone,reference,String(timestamp)].join("|"); const signature=await sign(secret,payload);
   const tokenRes=await providerPost("api/auth/marchand/withdrawal-token",{amount:Number(amount),method,recipient:phone,reference,timestamp,withdrawal_signature:signature},String(authData.token));
   const tokenData=await tokenRes.json().catch(()=>({}));
   if(!tokenRes.ok||tokenData.success!==true||!tokenData.withdrawal_token){ await admin.rpc("finish_wallet_withdrawal",{p_reference:reference,p_success:false,p_provider_transaction_id:null,p_fee_minor:0}); return json({error:tokenData.message??"Plop Plop a refusé la préparation du retrait."},502); }
   const executeRes=await providerPost("api/withdraw/marchand",{amount:Number(amount),method,recipient:phone,reference},String(tokenData.withdrawal_token));
   const executeData=await executeRes.json().catch(()=>({})); const wd=executeData.data??{}; const status=String(wd.status??"").toLowerCase();
   if(executeData.success===true&&status==="success") {
    const feeMinor=Math.round(Number(wd.fee??0)*100);
    const {error:finishError}=await admin.rpc("finish_wallet_withdrawal",{p_reference:reference,p_success:true,p_provider_transaction_id:String(wd.transaction_id??wd.api_reference??reference),p_fee_minor:feeMinor});
    if(finishError) return json({error:"Le fournisseur indique un retrait réussi mais l'enregistrement interne nécessite une réconciliation. Contacte le support avec la référence.",reference},500);
    return json({status:"successful",reference,amount_minor:amountMinor,fee_minor:feeMinor,message:executeData.message??"Retrait confirmé par Plop Plop."});
   }
   if(status==="failed"||executeData.success===false) {
    await admin.rpc("finish_wallet_withdrawal",{p_reference:reference,p_success:false,p_provider_transaction_id:null,p_fee_minor:0});
    return json({status:"failed",reference,error:executeData.message??"Le fournisseur a refusé le retrait."},400);
   }
   // Keep funds reserved as processing when the provider's answer is uncertain.
   await admin.from("wallet_transactions").update({metadata:{provider_status:status||"unknown",provider_response:executeData}}).eq("reference",reference).eq("user_id",user.id);
   return json({status:"processing",reference,message:"Le fournisseur n'a pas donné de confirmation finale. Ne relance pas le retrait; vérifie son statut ou contacte le support."},202);
  }
  if(action==="check_withdrawal") {
   const reference=String(b.reference??"");
   const {data:t,error}=await client.from("wallet_transactions").select("reference,status,amount_minor,fee_minor,user_id").eq("reference",reference).eq("user_id",user.id).eq("kind","withdrawal").maybeSingle();
   if(error||!t) return json({error:"Retrait introuvable"},404);
   if(t.status==="successful"||t.status==="failed") return json({status:t.status,reference});
   const authRes=await providerPost("api/auth/marchand",{client_id:clientId,client_secret:secret}); const authData=await authRes.json().catch(()=>({}));
   if(!authRes.ok||authData.success!==true||!authData.token) return json({error:"Impossible d'authentifier le compte marchand pour vérifier le retrait."},502);
   const vr=await providerPost("api/withdraw/marchand/verify",{reference},String(authData.token)); const vd=await vr.json().catch(()=>({})); const st=String(vd.data?.status??"").toLowerCase();
   if(vr.ok&&vd.success===true&&st==="success") { const feeMinor=Math.round(Number(vd.data?.amount??0)*100)-Number(t.amount_minor); const {error:fe}=await admin.rpc("finish_wallet_withdrawal",{p_reference:reference,p_success:true,p_provider_transaction_id:String(vd.data?.transaction_id??reference),p_fee_minor:Math.max(0,feeMinor)}); if(fe)return json({error:"Retrait confirmé par le fournisseur, rapprochement interne nécessaire",reference},500); return json({status:"successful",reference}); }
   if(vr.ok&&vd.success===true&&st==="failed") { await admin.rpc("finish_wallet_withdrawal",{p_reference:reference,p_success:false,p_provider_transaction_id:null,p_fee_minor:0}); return json({status:"failed",reference}); }
   return json({status:"processing",reference});
  }
  return json({error:"Action inconnue"},400);
 } catch(e) { return json({error:String((e as Error).message??e)},500); }
});
