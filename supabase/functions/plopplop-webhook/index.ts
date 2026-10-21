// Fonction Supabase "bazik-webhook" — appelée par Bazik (sans JWT : désactiver "Verify JWT" pour cette fonction).
// Bazik envoie { orderId }. On NE FAIT PAS confiance au contenu : on interroge Bazik (GET /order/{id}) avant de confirmer.
// Secrets : BAZIK_USER_ID, BAZIK_SECRET_KEY, BAZIK_WEBHOOK_SECRET.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BAZIK = "https://api.bazik.io";

let cached: { token: string; exp: number } | null = null;
async function bazikToken(): Promise<string> {
  if (cached && cached.exp > Date.now() + 60_000) return cached.token;
  const r = await fetch(`${BAZIK}/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ userID: Deno.env.get("BAZIK_USER_ID"), secretKey: Deno.env.get("BAZIK_SECRET_KEY") }),
  });
  if (!r.ok) throw new Error(`Authentification Bazik refusée (${r.status})`);
  const d = await r.json();
  cached = { token: d.access_token, exp: Date.now() + (Number(d.expires_in) || 3600) * 1000 };
  return cached.token;
}

async function hmacHex(secret: string, data: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("ok");
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const raw = await req.text();
  const header = req.headers.get("X-Bazik-Signature") ?? "";
  let payload: { orderId?: string } = {};
  try { payload = JSON.parse(raw); } catch { /* corps illisible */ }
  const orderId = payload.orderId ? String(payload.orderId) : null;

  // Signature : enregistrée à titre indicatif (l'algorithme exact n'est pas documenté publiquement).
  // La sécurité repose sur la revérification serveur-à-serveur ci-dessous.
  const secret = Deno.env.get("BAZIK_WEBHOOK_SECRET") ?? "";
  const expected = secret ? await hmacHex(secret, raw) : "";
  const sigOk = !!header && !!expected && header.replace(/^sha256=/i, "").toLowerCase() === expected;
  await admin.from("payment_events").insert({ provider_order_id: orderId, payload: payload as never, signature: header || null, signature_ok: sigOk });

  if (!orderId) return new Response("ignored");
  try {
    const { data: attempt } = await admin.from("payment_attempts").select("*").eq("provider_order_id", orderId).maybeSingle();
    if (!attempt) return new Response("unknown order");
    if (attempt.status === "successful") return new Response("already");
    const token = await bazikToken();
    const r = await fetch(`${BAZIK}/order/${encodeURIComponent(orderId)}`, { headers: { Authorization: `Bearer ${token}` } });
    if (!r.ok) return new Response("retry", { status: 502 });
    const d = await r.json();
    const st = String(d.status ?? "").toLowerCase();
    if (d.referenceId && d.referenceId !== attempt.id) return new Response("reference mismatch");
    if (st === "successful") {
      const paid = Number(d.gdes ?? d.amount);
      if (Number.isFinite(paid) && Math.abs(paid - attempt.amount_minor / 100) > 0.01) return new Response("amount mismatch");
      const { error } = await admin.rpc("apply_payment_success", { p_attempt: attempt.id });
      if (error) return new Response(error.message, { status: 500 });
      return new Response("paid");
    }
    if (st === "failed" || st === "cancelled") await admin.rpc("mark_payment_failed", { p_attempt: attempt.id, p_status: st });
    return new Response(st || "pending");
  } catch (e) {
    return new Response(String((e as Error).message ?? e), { status: 500 });
  }
});
