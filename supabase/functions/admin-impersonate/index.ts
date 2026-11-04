// Prise de contrôle d'un compte par un administrateur (support). Journalisée côté serveur.
// Secrets requis (fournis automatiquement par Supabase) : SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth) return json({ error: "Connexion requise" }, 401);

    const { user_id, reason } = await req.json();
    if (!user_id || typeof reason !== "string") return json({ error: "Paramètres manquants" }, 400);

    // 1) Vérifie, sous l'identité de l'appelant, qu'il est administrateur déverrouillé, et journalise.
    const caller = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { error: logErr } = await caller.rpc("admin_log_impersonation", { p_user: user_id, p_reason: reason });
    if (logErr) return json({ error: logErr.message }, 403);

    // 2) Génère un lien de connexion à usage unique pour le compte cible.
    const admin = createClient(url, svc);
    const { data: u, error: uErr } = await admin.auth.admin.getUserById(user_id);
    if (uErr || !u?.user?.email) return json({ error: "Ce compte n'a pas d'adresse e-mail utilisable" }, 400);
    const { data: link, error: lErr } = await admin.auth.admin.generateLink({ type: "magiclink", email: u.user.email });
    if (lErr || !link?.properties?.hashed_token) return json({ error: "Impossible de générer l'accès" }, 500);
    return json({ token_hash: link.properties.hashed_token, email: u.user.email });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
