// Fonction Supabase "delete-account" — appelée par l'application (JWT utilisateur requis).
// Anonymise les données personnelles (SQL anonymize_account), rend l'adresse e-mail inutilisable puis désactive le compte.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "Connexion requise" }, 401);
    const body = await req.json().catch(() => ({}));
    if (body.confirm !== "SUPPRIMER") return json({ error: "Confirmation manquante" }, 400);

    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { error } = await admin.rpc("anonymize_account", { p_user: user.id });
    if (error) return json({ error: error.message }, 400);

    await admin.auth.admin.updateUserById(user.id, { email: `deleted-${user.id}@haitiket.invalid`, user_metadata: {} });
    const { error: delErr } = await admin.auth.admin.deleteUser(user.id, true); // suppression « douce » : conserve l'intégrité des commandes
    if (delErr) return json({ error: delErr.message }, 500);
    return json({ ok: true });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
