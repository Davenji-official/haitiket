import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BASE = "https://plopplop.solutionip.app/";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Configuration serveur manquante : ${name}`);
  return value;
}

function amountMinor(value: unknown): number | null {
  const n = Number(value);
  if (!Number.isSafeInteger(n)) return null;
  if (n < 1 || n > 50_000_000) return null;
  return n;
}

function safeReference(prefix: string): string {
  return `${prefix}-${crypto.randomUUID().toUpperCase()}`;
}

function hex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((v) => v.toString(16).padStart(2, "0"))
    .join("");
}

async function hmac(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(payload),
    ),
  );
}

async function providerPost(
  path: string,
  body: unknown,
  token?: string,
): Promise<{ ok: boolean; status: number; data: Record<string, any> }> {
  const response = await fetch(new URL(path, BASE), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15_000),
  });

  const data = await response.json().catch(() => ({}));
  return {
    ok: response.ok,
    status: response.status,
    data: data && typeof data === "object" ? data : {},
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  if (req.method !== "POST") {
    return json({ error: "Méthode POST requise." }, 405);
  }

  let body: Record<string, unknown>;

  try {
    body = await req.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json({ error: "Corps JSON invalide." }, 400);
    }
  } catch {
    return json({ error: "Corps JSON invalide." }, 400);
  }

  try {
    const url = env("SUPABASE_URL");
    const anon = env("SUPABASE_ANON_KEY");
    const service = env("SUPABASE_SERVICE_ROLE_KEY");
    const clientId = env("PLOPPLOP_CLIENT_ID");
    const secret = env("PLOPPLOP_CLIENT_SECRET");

    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return json({ error: "Connexion requise." }, 401);
    }

    const client = createClient(url, anon, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: authData, error: authError } = await client.auth.getUser();
    const user = authData?.user;

    if (authError || !user) {
      return json({ error: "Session invalide ou expirée." }, 401);
    }

    const admin = createClient(url, service, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const action = String(body.action ?? "");

    // ---------------------------------------------------------------
    // RETRAIT : préparation et demande au fournisseur
    // ---------------------------------------------------------------
    if (action === "withdraw") {
      const amount = amountMinor(body.amount_minor);
      const phone = String(body.phone ?? "").trim();
      const method = String(body.method ?? "").toLowerCase();

      if (amount === null || amount < 5000) {
        return json({
          error: "Le retrait doit être compris entre 50 et 500 000 HTG.",
        }, 400);
      }

      if (!/^509\d{8}$/.test(phone)) {
        return json({ error: "Numéro haïtien invalide (509XXXXXXXX)." }, 400);
      }

      if (!["moncash", "natcash"].includes(method)) {
        return json({ error: "Méthode de retrait non prise en charge." }, 400);
      }

      const reference = safeReference("HTKW");

      // Cette fonction SQL doit vérifier le solde et réserver les fonds
      // de manière atomique avant que le fournisseur soit appelé.
      const { error: prepareError } = await client.rpc(
        "prepare_wallet_withdrawal",
        {
          p_amount_minor: amount,
          p_currency: "HTG",
          p_phone: phone,
          p_reference: reference,
        },
      );

      if (prepareError) {
        return json({
          error: "Impossible de préparer le retrait.",
          code: "WITHDRAWAL_PREPARATION_FAILED",
        }, 400);
      }

      let authResult: Awaited<ReturnType<typeof providerPost>>;

      try {
        authResult = await providerPost("api/auth/marchand", {
          client_id: clientId,
          client_secret: secret,
        });
      } catch {
        // L'authentification n'exécute pas le transfert.
        await admin.rpc("finish_wallet_withdrawal", {
          p_reference: reference,
          p_success: false,
          p_provider_transaction_id: null,
          p_fee_minor: 0,
        });

        return json({
          error: "Le fournisseur est temporairement inaccessible.",
          reference,
        }, 502);
      }

      const merchantToken = authResult.data.token;

      if (!authResult.ok ||
          authResult.data.success !== true ||
          typeof merchantToken !== "string" ||
          !merchantToken) {
        await admin.rpc("finish_wallet_withdrawal", {
          p_reference: reference,
          p_success: false,
          p_provider_transaction_id: null,
          p_fee_minor: 0,
        });

        return json({
          error: "Authentification marchand refusée par le fournisseur.",
          reference,
        }, 502);
      }

      // Le montant est exprimé en HTG dans l'API fournisseur.
      const amountHTG = amount / 100;
      const amountString = amountHTG.toFixed(2);
      const timestamp = Math.floor(Date.now() / 1000);

      // La documentation exige :
      // amount|method|recipient|reference|timestamp
      const signedPayload = [
        amountString,
        method,
        phone,
        reference,
        String(timestamp),
      ].join("|");

      const signature = await hmac(secret, signedPayload);

      let tokenResult: Awaited<ReturnType<typeof providerPost>>;

      try {
        tokenResult = await providerPost(
          "api/auth/marchand/withdrawal-token",
          {
            amount: Number(amountString),
            method,
            recipient: phone,
            reference,
            timestamp,
            withdrawal_signature: signature,
          },
          merchantToken,
        );
      } catch {
        await admin.rpc("finish_wallet_withdrawal", {
          p_reference: reference,
          p_success: false,
          p_provider_transaction_id: null,
          p_fee_minor: 0,
        });

        return json({
          error: "Impossible de préparer le retrait chez le fournisseur.",
          reference,
        }, 502);
      }

      const withdrawalToken = tokenResult.data.withdrawal_token;

      if (!tokenResult.ok ||
          tokenResult.data.success !== true ||
          typeof withdrawalToken !== "string" ||
          !withdrawalToken) {
        await admin.rpc("finish_wallet_withdrawal", {
          p_reference: reference,
          p_success: false,
          p_provider_transaction_id: null,
          p_fee_minor: 0,
        });

        return json({
          error: "Le fournisseur a refusé la préparation du retrait.",
          reference,
        }, 502);
      }

      let executeResult: Awaited<ReturnType<typeof providerPost>>;

      try {
        executeResult = await providerPost(
          "api/withdraw/marchand",
          {
            amount: Number(amountString),
            method,
            recipient: phone,
            reference,
          },
          withdrawalToken,
        );
      } catch {
        // Le transfert peut avoir été exécuté malgré le timeout.
        // Ne pas le marquer échoué et ne pas relancer automatiquement.
        await admin.from("wallet_transactions")
          .update({
            metadata: {
              reconciliation_required: true,
              provider_status: "unknown_after_request",
            },
          })
          .eq("reference", reference)
          .eq("user_id", user.id);

        return json({
          status: "processing",
          reference,
          message:
            "Résultat du retrait inconnu. Ne recommence pas cette opération. Vérifie son statut avant toute nouvelle demande.",
        }, 202);
      }

      const result = executeResult.data;
      const transfer = result.data ?? {};
      const status = String(transfer.status ?? "").toLowerCase();

      if (executeResult.ok &&
          result.success === true &&
          status === "success") {
        // L'API documente api_reference comme identifiant numérique
        // du transfert externe. Il est obligatoire ici pour le suivi.
        const apiReference = String(transfer.api_reference ?? "");

        if (!/^\d+$/.test(apiReference)) {
          await admin.from("wallet_transactions")
            .update({
              metadata: {
                reconciliation_required: true,
                provider_status: "success_missing_numeric_api_reference",
              },
            })
            .eq("reference", reference)
            .eq("user_id", user.id);

          return json({
            status: "review",
            reference,
            message:
              "Le fournisseur annonce un succès, mais l'identifiant externe doit être rapproché manuellement. Ne relance pas ce retrait.",
          }, 202);
        }

        const fee = Number(transfer.fee);
        if (!Number.isFinite(fee) || fee < 0) {
          await admin.from("wallet_transactions")
            .update({
              metadata: {
                reconciliation_required: true,
                provider_status: "success_invalid_fee",
                provider_api_reference: apiReference,
              },
            })
            .eq("reference", reference)
            .eq("user_id", user.id);

          return json({
            status: "review",
            reference,
            message:
              "Le fournisseur annonce un succès, mais les frais doivent être rapprochés avant clôture.",
          }, 202);
        }

        const feeMinor = Math.round(fee * 100);

        const { error: finishError } = await admin.rpc(
          "finish_wallet_withdrawal",
          {
            p_reference: reference,
            p_success: true,
            p_provider_transaction_id: apiReference,
            p_fee_minor: feeMinor,
          },
        );

        if (finishError) {
          await admin.from("wallet_transactions")
            .update({
              metadata: {
                reconciliation_required: true,
                provider_status: "success_internal_update_failed",
                provider_api_reference: apiReference,
              },
            })
            .eq("reference", reference)
            .eq("user_id", user.id);

          return json({
            status: "review",
            reference,
            message:
              "Le fournisseur confirme le retrait, mais HAITIKET doit rapprocher l'opération. Ne recommence pas le retrait.",
          }, 202);
        }

        return json({
          status: "successful",
          reference,
          amount_minor: amount,
          fee_minor: feeMinor,
          message: "Retrait confirmé par le fournisseur.",
        });
      }

      // Seul un échec explicite documenté peut être clôturé comme échoué.
      if (result.success === false && status === "failed") {
        await admin.rpc("finish_wallet_withdrawal", {
          p_reference: reference,
          p_success: false,
          p_provider_transaction_id: null,
          p_fee_minor: 0,
        });

        return json({
          status: "failed",
          reference,
          error: "Le fournisseur a confirmé l'échec du retrait.",
        }, 400);
      }

      // Réponse inattendue ou ambiguë : garder la demande en traitement.
      await admin.from("wallet_transactions")
        .update({
          metadata: {
            reconciliation_required: true,
            provider_status: status || "unknown",
            provider_http_status: executeResult.status,
          },
        })
        .eq("reference", reference)
        .eq("user_id", user.id);

      return json({
        status: "processing",
        reference,
        message:
          "Le résultat doit être vérifié auprès du fournisseur. Ne relance pas cette demande.",
      }, 202);
    }

    // ---------------------------------------------------------------
    // VÉRIFIER UN RETRAIT EXISTANT
    // ---------------------------------------------------------------
    if (action === "check_withdrawal") {
      const reference = String(body.reference ?? "").trim();

      if (!/^HTKW-[A-F0-9-]{20,60}$/.test(reference)) {
        return json({ error: "Référence de retrait invalide." }, 400);
      }

      const { data: transaction, error: readError } = await client
        .from("wallet_transactions")
        .select("reference,status,amount_minor,fee_minor,user_id")
        .eq("reference", reference)
        .eq("user_id", user.id)
        .eq("kind", "withdrawal")
        .maybeSingle();

      if (readError || !transaction) {
        return json({ error: "Retrait introuvable." }, 404);
      }

      if (["successful", "failed"].includes(transaction.status)) {
        return json({
          status: transaction.status,
          reference,
        });
      }

      let authResult: Awaited<ReturnType<typeof providerPost>>;

      try {
        authResult = await providerPost("api/auth/marchand", {
          client_id: clientId,
          client_secret: secret,
        });
      } catch {
        return json({
          status: "processing",
          reference,
          message: "Fournisseur temporairement inaccessible.",
        }, 202);
      }

      const merchantToken = authResult.data.token;

      if (!authResult.ok ||
          authResult.data.success !== true ||
          typeof merchantToken !== "string" ||
          !merchantToken) {
        return json({
          status: "processing",
          reference,
          message: "Impossible d'authentifier le compte marchand.",
        }, 202);
      }

      let verifyResult: Awaited<ReturnType<typeof providerPost>>;

      try {
        verifyResult = await providerPost(
          "api/withdraw/marchand/verify",
          { reference },
          merchantToken,
        );
      } catch {
        return json({
          status: "processing",
          reference,
          message: "Vérification temporairement indisponible.",
        }, 202);
      }

      const verified = verifyResult.data;
      const transfer = verified.data ?? {};
      const status = String(transfer.status ?? "").toLowerCase();

      if (!verifyResult.ok || verified.success !== true) {
        return json({
          status: "processing",
          reference,
          message: "Le fournisseur n'a pas confirmé le statut final.",
        }, 202);
      }

      if (status === "success") {
        const apiReference = String(
          transfer.provider?.transactionId ??
          transfer.api_reference ??
          "",
        );

        // La réponse de vérification peut ne pas inclure api_reference.
        // Ne pas substituer arbitrairement la référence interne.
        if (!/^\d+$/.test(apiReference)) {
          await admin.from("wallet_transactions")
            .update({
              metadata: {
                reconciliation_required: true,
                provider_status: "success_missing_numeric_api_reference",
              },
            })
            .eq("reference", reference)
            .eq("user_id", user.id);

          return json({
            status: "review",
            reference,
            message:
              "Le fournisseur indique un succès. L'identifiant externe doit être rapproché avant clôture.",
          }, 202);
        }

        const providerAmount = Number(transfer.amount);
        if (!Number.isFinite(providerAmount) || providerAmount <= 0) {
          return json({
            status: "review",
            reference,
            message: "Montant fournisseur invalide : rapprochement requis.",
          }, 202);
        }

        // Le champ amount de l'endpoint verify représente le total
        // dans l'exemple de la documentation. On ne l'utilise donc
        // pas pour calculer les frais sans ventilation confirmée.
        const feeMinor = 0;

        const { error: finishError } = await admin.rpc(
          "finish_wallet_withdrawal",
          {
            p_reference: reference,
            p_success: true,
            p_provider_transaction_id: apiReference,
            p_fee_minor: feeMinor,
          },
        );

        if (finishError) {
          return json({
            status: "review",
            reference,
            message: "Rapprochement interne requis.",
          }, 202);
        }

        return json({ status: "successful", reference });
      }

      if (status === "failed") {
        const { error: finishError } = await admin.rpc(
          "finish_wallet_withdrawal",
          {
            p_reference: reference,
            p_success: false,
            p_provider_transaction_id: null,
            p_fee_minor: 0,
          },
        );

        if (finishError) {
          return json({
            status: "review",
            reference,
            message: "Impossible d'enregistrer l'échec confirmé.",
          }, 202);
        }

        return json({ status: "failed", reference });
      }

      // pending, refunded, ou statut inconnu : ne pas créditer ni débiter.
      return json({
        status: "processing",
        reference,
        provider_status: status || "unknown",
      }, 202);
    }

    return json({
      error: "Action inconnue. Actions acceptées : withdraw, check_withdrawal.",
    }, 400);
  } catch {
    return json({
      error: "Erreur interne. Consulte les logs sécurisés de la fonction.",
    }, 500);
  }
});
