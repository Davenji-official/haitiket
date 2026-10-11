// Fonction Supabase "bazik-pay" — appelée par l'application (JWT utilisateur requis).
// Actions : { action: "create", purpose: "order"|"bazar_listing"|"shop_plan", target_id } -> { redirectUrl }
//           { action: "check",  purpose, target_id } -> vérifie auprès de Bazik et confirme si payé.
// Secrets requis (Supabase > Edge Functions > Secrets) : BAZIK_USER_ID, BAZIK_SECRET_KEY, SITE_URL (facultatif).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BAZIK = "https://api.bazik.io";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

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

// deno-lint-ignore no-explicit-any
async function reconcile(admin: any, token: string, attempt: any) {
  const r = await fetch(`${BAZIK}/order/${encodeURIComponent(attempt.provider_order_id)}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!r.ok) return { status: attempt.status, note: `bazik ${r.status}` };
  const d = await r.json();
  const st = String(d.status ?? "").toLowerCase();
  if (d.referenceId && d.referenceId !== attempt.id) return { status: attempt.status, note: "reference différente" };
  if (st === "successful") {
    const paid = Number(d.gdes ?? d.amount);
    if (Number.isFinite(paid) && Math.abs(paid - attempt.amount_minor / 100) > 0.01) return { status: attempt.status, note: "montant différent" };
    const { data, error } = await admin.rpc("apply_payment_success", { p_attempt: attempt.id });
    if (error) throw new Error(error.message);
    return { status: "successful", result: data };
  }
  if (st === "failed" || st === "cancelled") {
    await admin.rpc("mark_payment_failed", { p_attempt: attempt.id, p_status: st });
    return { status: st };
  }
  return { status: st || "pending" };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "Connexion requise" }, 401);
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const body = await req.json();
    const purpose = String(body.purpose ?? "order");
    const target = String(body.target_id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(target)) return json({ error: "Cible invalide" }, 400);

    if (body.action === "create") {
      const { data: attempt, error } = await admin.rpc("start_payment", { p_purpose: purpose, p_target: target, p_user: user.id });
      if (error) return json({ error: error.message }, 400);
      const { data: prof } = await admin.from("profiles").select("display_name").eq("id", user.id).maybeSingle();
      const parts = String(prof?.display_name ?? "Client HAITIKET").trim().split(/\s+/);
      const site = (Deno.env.get("SITE_URL") ?? "https://davenji-official.github.io/haitiket/").replace(/\/?$/, "/");
      const token = await bazikToken();
      const amount = attempt.amount_minor / 100;
      const r = await fetch(`${BAZIK}/moncash/token`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          gdes: amount,
          referenceId: attempt.id,
          webhookUrl: `${url}/functions/v1/bazik-webhook`,
          description: purpose === "order" ? "Commande HAITIKET" : purpose === "bazar_listing" ? "Annonce Bazar HAITIKET (14 jours)" : "Abonnement boutique HAITIKET (30 jours)",
          customerFirstName: parts[0],
          customerLastName: parts.slice(1).join(" ") || parts[0],
          customerEmail: user.email ?? undefined,
          successUrl: `${site}?pay=success`,
          errorUrl: `${site}?pay=error`,
        }),
      });
      const d = await r.json().catch(() => ({}));
      if (!r.ok || !d.redirectUrl || !d.orderId) {
        await admin.rpc("mark_payment_failed", { p_attempt: attempt.id, p_status: "failed" });
        return json({ error: "Paiement refusé par Bazik", status: r.status, detail: d?.message ?? d?.error ?? null }, 502);
      }
      await admin.rpc("attach_provider_order", { p_attempt: attempt.id, p_provider_order: String(d.orderId), p_url: String(d.redirectUrl) });
      return json({ redirectUrl: d.redirectUrl, attemptId: attempt.id });
    }

    if (body.action === "check") {
      const { data: attempts } = await admin.from("payment_attempts").select("*")
        .eq("user_id", user.id).eq("purpose", purpose).eq("target_id", target).in("status", ["created", "pending"]).not("provider_order_id", "is", null);
      const token = await bazikToken();
      const results = [];
      for (const a of attempts ?? []) results.push(await reconcile(admin, token, a));
      return json({ results });
    }
    return json({ error: "Action inconnue" }, 400);
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
