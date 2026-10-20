import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"Content-Type":"application/json"}});
const hex=(b:ArrayBuffer)=>Array.from(new Uint8Array(b)).map(x=>x.toString(16).padStart(2,"0")).join("");
async function hmac(secret:string,body:string){const k=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);return hex(await crypto.subtle.sign("HMAC",k,new TextEncoder().encode(body)));}
Deno.serve(async(req)=>{
 if(req.method!=="POST")return json({error:"POST requis"},405);
 const raw=await req.text(); const secret=Deno.env.get("PLOPPLOP_CLIENT_SECRET")??""; const sig=req.headers.get("X-Webhook-Signature")??"";
 if(!secret||!sig.startsWith("sha256="))return json({error:"Signature absente"},401);
 const expected="sha256="+await hmac(secret,raw); if(expected.length!==sig.length||![...expected].reduce((ok,c,i)=>ok&&(c===sig[i]),true))return json({error:"Signature invalide"},401);
 try{
  const payload=JSON.parse(raw); const tx=payload.transaction??{}; const reference=String(tx.reference_id??tx.refference_id??"");
  if(!reference.startsWith("HTK-"))return json({received:true,ignored:true});
  const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  // Webhooks are best-effort: independently verify with payment-verify before credit.
  const r=await fetch("https://plopplop.solutionip.app/api/paiement-verify",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({client_id:Deno.env.get("PLOPPLOP_CLIENT_ID"),refference_id:reference})});
  const d=await r.json().catch(()=>({})); if(!r.ok||d.trans_status!=="ok")return json({received:true,credited:false,status:d.trans_status??"pending"});
  const amount=Math.round(Number(d.montant)*100); const {error}=await admin.rpc("confirm_wallet_topup",{p_reference:reference,p_provider_transaction_id:String(d.transaction_id??tx.transaction_id??""),p_provider_amount_minor:amount});
  if(error)return json({error:error.message},409); return json({received:true,credited:true});
 }catch(e){return json({error:String((e as Error).message??e)},500);}
});
