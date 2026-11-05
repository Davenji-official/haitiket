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

    // 1) Vérifie, sous l'identité de l'appelant, qu'il est administrateur déverrouillé ; journalise ; lève temporairement
    //    le blocage de connexion si le compte est bloqué/supprimé par l'administration (session de support de 20 min).
    const caller = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data: began, error: logErr } = await caller.rpc("admin_begin_support_session", { p_user: user_id, p_reason: reason });
    if (logErr) return json({ error: logErr.message }, 403);

    const rollback = async () => { if (began?.was_banned) await caller.rpc("admin_end_support_session", { p_user: user_id }); };

    // 2) Génère un lien de connexion à usage unique pour le compte cible.
    const admin = createClient(url, svc);
    const { data: u, error: uErr } = await admin.auth.admin.getUserById(user_id);
    if (uErr || !u?.user?.email || (u.user as { deleted_at?: string }).deleted_at) {
      await rollback();
      return json({ error: "Compte supprimé définitivement par son propriétaire ou sans e-mail : consultation seule (fiche 360°)." }, 400);
    }
    const { data: link, error: lErr } = await admin.auth.admin.generateLink({ type: "magiclink", email: u.user.email });
    if (lErr || !link?.properties?.hashed_token) {
      await rollback();
      return json({ error: "Impossible de générer l'accès" }, 500);
    }
    return json({ token_hash: link.properties.hashed_token, email: u.user.email, was_banned: !!began?.was_banned });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
