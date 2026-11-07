// Webhook Plop Plop (événements transaction.created / transaction.status_changed).
// IMPORTANT : cette fonction doit être déployée SANS vérification JWT (Plop Plop n'envoie pas de jeton Supabase) :
//   supabase functions deploy plopplop-webhook --no-verify-jwt
// (ou, dans le tableau de bord Supabase : Edge Functions > plopplop-webhook > désactiver « Verify JWT »).
// Secrets requis : PLOPPLOP_CLIENT_ID, PLOPPLOP_CLIENT_SECRET (SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont automatiques).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });
const hex = (b: ArrayBuffer) => Array.from(new Uint8Array(b)).map((x) => x.toString(16).padStart(2, "0")).join("");
async function hmac(secret: string, body: string) {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(body)));
}
function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

Deno.serve(async (req) => {
  const url = Deno.env.get("SUPABASE_URL");
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const admin = url && svc ? createClient(url, svc) : null;
  const log = async (o: { event?: string; reference?: string; signature_ok?: boolean; outcome: string; http_status: number; detail?: string }) => {
    try { await admin?.from("payment_webhook_events").insert({ provider: "plopplop", ...o }); } catch { /* journal facultatif */ }
  };

  if (req.method !== "POST") return json({ error: "POST requis" }, 405);
  const raw = await req.text();
  const secret = Deno.env.get("PLOPPLOP_CLIENT_SECRET") ?? "";
  const sig = req.headers.get("X-Webhook-Signature") ?? "";

  if (!secret) { await log({ outcome: "secret_absent", http_status: 401, detail: "PLOPPLOP_CLIENT_SECRET non configuré" }); return json({ error: "Secret absent" }, 401); }
  if (!sig.startsWith("sha256=")) { await log({ outcome: "signature_absente", http_status: 401 }); return json({ error: "Signature absente" }, 401); }
  const expected = "sha256=" + await hmac(secret, raw);
  if (!safeEqual(expected, sig)) { await log({ outcome: "signature_invalide", signature_ok: false, http_status: 401, detail: "Le client_secret ne correspond pas à celui de Plop Plop" }); return json({ error: "Signature invalide" }, 401); }

  try {
    const payload = JSON.parse(raw);
    const tx = payload.transaction ?? {};
    const event = String(payload.event ?? "");
    const reference = String(tx.reference_id ?? tx.refference_id ?? "");
    if (!reference.startsWith("HTK-")) { await log({ event, reference, signature_ok: true, outcome: "ignoree", http_status: 200, detail: "Référence non HAITIKET" }); return json({ received: true, ignored: true }); }
    if (!admin) { await log({ event, reference, signature_ok: true, outcome: "erreur_config", http_status: 500, detail: "SUPABASE_SERVICE_ROLE_KEY absent" }); return json({ error: "Configuration" }, 500); }

    // Les webhooks sont « best-effort » : on revérifie TOUJOURS auprès de Plop Plop avant de créditer.
    const r = await fetch("https://plopplop.solutionip.app/api/paiement-verify", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ client_id: Deno.env.get("PLOPPLOP_CLIENT_ID"), refference_id: reference }),
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok || d.trans_status !== "ok") {
      await log({ event, reference, signature_ok: true, outcome: "pas_encore_paye", http_status: 200, detail: `verify http=${r.status} statut=${d.trans_status ?? "?"}` });
      return json({ received: true, credited: false, status: d.trans_status ?? "pending" });
    }
    const amount = Math.round(Number(d.montant) * 100);
    const { error } = await admin.rpc("confirm_wallet_topup", { p_reference: reference, p_provider_transaction_id: String(d.transaction_id ?? tx.transaction_id ?? ""), p_provider_amount_minor: amount });
    if (error) { await log({ event, reference, signature_ok: true, outcome: "erreur_credit", http_status: 409, detail: error.message }); return json({ error: error.message }, 409); }
    await log({ event, reference, signature_ok: true, outcome: "credite", http_status: 200, detail: `${amount / 100} HTG` });
    return json({ received: true, credited: true });
  } catch (e) {
    await log({ outcome: "exception", http_status: 500, detail: String((e as Error).message ?? e) });
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
