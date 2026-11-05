// Envoi des notifications push (FCM HTTP v1). Déclenchée par un « Database Webhook » sur INSERT dans public.notifications.
// Secrets : FCM_SERVICE_ACCOUNT (JSON complet du compte de service Firebase), PUSH_WEBHOOK_SECRET (valeur libre, identique dans l'en-tête du webhook),
//           SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY (fournis automatiquement).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const b64url = (b: ArrayBuffer | string) => {
  const bytes = typeof b === "string" ? new TextEncoder().encode(b) : new Uint8Array(b);
  let s = ""; bytes.forEach((x) => (s += String.fromCharCode(x)));
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function accessToken(sa: { client_email: string; private_key: string; token_uri?: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: sa.token_uri ?? "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`));
  const jwt = `${header}.${claim}.${b64url(sig)}`;
  const r = await fetch(sa.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error("OAuth FCM refusé : " + JSON.stringify(j));
  return j.access_token;
}

Deno.serve(async (req) => {
  try {
    if (req.headers.get("x-webhook-secret") !== Deno.env.get("PUSH_WEBHOOK_SECRET")) return new Response("forbidden", { status: 403 });
    const payload = await req.json();
    const rec = payload.record ?? payload;
    if (!rec?.user_id || !rec?.title) return new Response("ignored", { status: 200 });

    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: tokens } = await db.from("push_tokens").select("token").eq("user_id", rec.user_id);
    if (!tokens || tokens.length === 0) return new Response("no tokens", { status: 200 });

    const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
    const at = await accessToken(sa);
    const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
    const dead: string[] = [];
    await Promise.all(tokens.map(async (t: { token: string }) => {
      const r = await fetch(url, {
        method: "POST", headers: { Authorization: `Bearer ${at}`, "Content-Type": "application/json" },
        body: JSON.stringify({ message: {
          token: t.token,
          notification: { title: String(rec.title).slice(0, 100), body: String(rec.body ?? "").slice(0, 200), ...(rec.image_url ? { image: rec.image_url } : {}) },
          data: { kind: String(rec.kind ?? ""), ref: String(rec.ref ?? ""), link_url: String(rec.link_url ?? "") },
          android: { priority: "HIGH", notification: { channel_id: "haitiket_default", sound: "default" } },
        } }),
      });
      if (!r.ok) {
        const e = await r.text();
        if (e.includes("UNREGISTERED") || e.includes("INVALID_ARGUMENT")) dead.push(t.token);
      }
    }));
    if (dead.length) await db.from("push_tokens").delete().in("token", dead);
    return new Response("ok", { status: 200 });
  } catch (e) {
    return new Response(String((e as Error).message ?? e), { status: 500 });
  }
});
