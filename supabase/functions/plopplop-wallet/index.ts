import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BASE_URL = "https://plopplop.solutionip.app/";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

type JsonObject = Record<string, unknown>;

function response(body: JsonObject, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: CORS_HEADERS,
  });
}

function getEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Configuration serveur manquante : ${name}`);
  return value;
}

function parseAmount(value: unknown): number | null {
  const amount = Number(value);

  if (
    !Number.isSafeInteger(amount) ||
    amount < 2000 ||
    amount > 50000000
  ) {
    return null;
  }

  return amount;
}

function validReference(value: string): boolean {
  return /^HTK-[A-F0-9-]{20,60}$/.test(value);
}

async function providerRequest(
  path: string,
  body: JsonObject,
): Promise<{ ok: boolean; status: number; data: JsonObject }> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);

  try {
    const result = await fetch(new URL(path, BASE_URL), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    const data = await result.json().catch(() => ({}));

    return {
      ok: result.ok,
      status: result.status,
      data: data as JsonObject,
    };
  } finally {
    clearTimeout(timeout);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return response({ error: "Méthode non autorisée." }, 405);
  }

  try {
    const supabaseUrl = getEnv("SUPABASE_URL");
    const anonKey = getEnv("SUPABASE_ANON_KEY");
    const serviceKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");
    const clientId = getEnv("PLOPPLOP_CLIENT_ID");

    // Vérification de la session de l'utilisateur.
    const authorization = req.headers.get("Authorization");

    if (!authorization?.startsWith("Bearer ")) {
      return response({ error: "Connexion requise." }, 401);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: {
        headers: { Authorization: authorization },
      },
    });

    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();

    if (authError || !user) {
      return response({ error: "Session invalide ou expirée." }, 401);
    }

    const admin = createClient(supabaseUrl, serviceKey);

    let body: JsonObject;

    try {
      body = await req.json();
    } catch {
      return response({ error: "Corps JSON invalide." }, 400);
    }

    const action = String(body.action ?? "");

    // Vérifier que le secret marchand existe sans jamais l'exposer.
    if (!Deno.env.get("PLOPPLOP_CLIENT_SECRET")) {
      return response(
        { error: "Le fournisseur de paiement n'est pas configuré." },
        503,
      );
    }

    // ---------------------------------------------------------
    // ACTION 1 : CRÉER UNE RECHARGE
    // ---------------------------------------------------------
    if (action === "topup") {
      // amount_minor représente le montant à créditer dans le portefeuille choisi.
      const amountMinor = parseAmount(body.amount_minor);
      const currency = String(body.currency ?? "HTG").toUpperCase();
      const method = String(body.method ?? "");
      const phone = String(body.phone ?? "").trim();

      if (amountMinor === null) {
        return response(
          { error: "Montant invalide. Minimum : 20 unités de la devise choisie." },
          400,
        );
      }

      if (currency !== "HTG" && currency !== "USD") {
        return response({ error: "Devise de portefeuille invalide." }, 400);
      }

      // Le fournisseur Plop Plop est payé en HTG, même pour créditer le portefeuille USD.
      let exchangeRate: number | null = null;
      let providerAmountMinor = amountMinor;
      if (currency === "USD") {
        const { data: setting, error: rateError } = await admin
          .from("platform_settings")
          .select("value")
          .eq("key", "usd_htg_rate")
          .maybeSingle();
        const parsedRate = Number(setting?.value);
        if (rateError || !Number.isFinite(parsedRate) || parsedRate <= 0) {
          return response({ error: "Le taux USD → HTG n'est pas configuré par l'administration." }, 503);
        }
        exchangeRate = parsedRate;
        providerAmountMinor = Math.round((amountMinor / 100) * exchangeRate * 100);
        if (!Number.isSafeInteger(providerAmountMinor) || providerAmountMinor < 2000 || providerAmountMinor > 50000000) {
          return response({ error: "Le montant converti en HTG est hors des limites du fournisseur." }, 400);
        }
      }

      const allowedMethods = [
        "moncash",
        "moncash_ussd",
        "natcash",
        "natcash_ussd",
      ];

      if (!allowedMethods.includes(method)) {
        return response({ error: "Méthode de paiement invalide." }, 400);
      }

      // Valider le numéro AVANT de créer une transaction.
      if (method.endsWith("_ussd") && !/^509[0-9]{8}$/.test(phone)) {
        return response(
          { error: "Entre un numéro haïtien au format 509XXXXXXXX." },
          400,
        );
      }

      const reference = `HTK-${crypto.randomUUID().toUpperCase()}`;

      // Créer une intention en attente. Aucun crédit à ce stade.
      const { data: transactionId, error: createError } =
        await userClient.rpc("create_wallet_topup_fx", {
          p_amount_minor: amountMinor,
          p_currency: currency,
          p_reference: reference,
          p_provider_amount_minor: providerAmountMinor,
          p_exchange_rate: exchangeRate,
        });

      if (createError || !transactionId) {
        return response(
          { error: "Impossible de créer la demande de recharge." },
          400,
        );
      }

      const payload: JsonObject = {
        client_id: clientId,
        refference_id: reference,
        montant: providerAmountMinor / 100,
        payment_method: method,
      };

      if (method.endsWith("_ussd")) {
        payload.phone_number = phone;
      }

      let providerResult: Awaited<ReturnType<typeof providerRequest>>;

      try {
        providerResult = await providerRequest(
          "api/paiement-marchand",
          payload,
        );
      } catch {
        // Ne pas déclarer le paiement réussi ou échoué sans confirmation.
        await admin
          .from("wallet_transactions")
          .update({
            status: "review",
            metadata: {
              reason: "provider_timeout_or_network_error",
              method,
              provider_amount_minor: providerAmountMinor,
              payment_currency: "HTG",
              wallet_currency: currency,
              exchange_rate: exchangeRate,
            },
          })
          .eq("id", transactionId)
          .eq("user_id", user.id);

        return response(
          {
            error:
              "Le fournisseur n'a pas répondu. Vérifie le statut avant de recommencer.",
            reference,
            status: "review",
          },
          502,
        );
      }

      const providerData = providerResult.data;
      const providerTransactionId = String(
        providerData.transaction_id ?? "",
      );

      if (
        !providerResult.ok ||
        providerData.status !== true ||
        !providerTransactionId
      ) {
        await admin
          .from("wallet_transactions")
          .update({
            status: "review",
            metadata: {
              reason: "provider_creation_unconfirmed",
              method,
              provider_http_status: providerResult.status,
              provider_amount_minor: providerAmountMinor,
              payment_currency: "HTG",
              wallet_currency: currency,
              exchange_rate: exchangeRate,
            },
          })
          .eq("id", transactionId)
          .eq("user_id", user.id);

        return response(
          {
            error:
              "La création du paiement n'a pas pu être confirmée. Vérification nécessaire avant toute nouvelle tentative.",
            reference,
            status: "review",
          },
          502,
        );
      }

      const { error: updateError } = await admin
        .from("wallet_transactions")
        .update({
          status: "pending",
          provider_transaction_id: providerTransactionId,
          metadata: {
            method,
            provider_message:
              typeof providerData.message === "string"
                ? providerData.message
                : null,
            provider_amount_minor: providerAmountMinor,
            payment_currency: "HTG",
            wallet_currency: currency,
            exchange_rate: exchangeRate,
          },
          updated_at: new Date().toISOString(),
        })
        .eq("id", transactionId)
        .eq("user_id", user.id);

      if (updateError) {
        // Le fournisseur a pu créer le paiement : ne pas le recréer.
        return response(
          {
            error:
              "Le paiement a été créé chez le fournisseur, mais son enregistrement interne doit être vérifié.",
            reference,
            status: "review",
          },
          500,
        );
      }

      return response({
        reference,
        transaction_id: providerTransactionId,
        redirect_url:
          typeof providerData.url === "string" ? providerData.url : null,
        status: "pending",
        wallet_currency: currency,
        wallet_amount_minor: amountMinor,
        provider_amount_minor: providerAmountMinor,
        exchange_rate: exchangeRate,
        message: method.endsWith("_ussd")
          ? "Vérifie ton téléphone et confirme la demande USSD."
          : "Suis les instructions du fournisseur pour terminer le paiement.",
      });
    }

    // ---------------------------------------------------------
    // ACTION 2 : VÉRIFIER UNE RECHARGE
    // ---------------------------------------------------------
    if (action === "check_topup") {
      const reference = String(body.reference ?? "");

      if (!validReference(reference)) {
        return response({ error: "Référence invalide." }, 400);
      }

      const { data: transaction, error: readError } = await userClient
        .from("wallet_transactions")
        .select(
          "reference,amount_minor,currency,status,provider_transaction_id,metadata",
        )
        .eq("reference", reference)
        .eq("user_id", user.id)
        .eq("kind", "topup")
        .maybeSingle();

      if (readError || !transaction) {
        return response({ error: "Recharge introuvable." }, 404);
      }

      if (transaction.status === "successful") {
        return response({ status: "successful", reference });
      }

      if (
        transaction.status === "failed" ||
        transaction.status === "review" ||
        transaction.status === "reversed"
      ) {
        return response({
          status: transaction.status,
          reference,
          message:
            "Cette opération nécessite une vérification ou une intervention.",
        });
      }

      let verification: Awaited<ReturnType<typeof providerRequest>>;

      try {
        verification = await providerRequest("api/paiement-verify", {
          client_id: clientId,
          refference_id: reference,
        });
      } catch {
        return response(
          {
            error: "Vérification temporairement indisponible.",
            status: transaction.status,
            reference,
          },
          502,
        );
      }

      const providerData = verification.data;

      if (!verification.ok || providerData.status !== true) {
        return response(
          {
            error: "Le fournisseur n'a pas confirmé le statut du paiement.",
            status: transaction.status,
            reference,
          },
          502,
        );
      }

      const providerStatus = String(providerData.trans_status ?? "");

      if (providerStatus !== "ok") {
        if (providerStatus === "failed") {
          // Ne pas transformer automatiquement une réponse incertaine
          // en échec définitif sans confirmer la sémantique du fournisseur.
          return response({
            status: "review",
            reference,
            message: "Le statut doit être rapproché avec le fournisseur.",
          });
        }

        return response({ status: "pending", reference });
      }

      const providerAmount = Number(providerData.montant);
      const amountMinor = Math.round(providerAmount * 100);

      const transactionMetadata = (transaction.metadata ?? {}) as JsonObject;
      const expectedProviderAmount = Number(
        transactionMetadata.provider_amount_minor ?? transaction.amount_minor,
      );
      if (
        !Number.isSafeInteger(amountMinor) ||
        amountMinor !== expectedProviderAmount ||
        transactionMetadata.payment_currency !== "HTG"
      ) {
        await admin
          .from("wallet_transactions")
          .update({
            status: "review",
            metadata: {
              reason: "provider_amount_or_currency_mismatch",
            },
            updated_at: new Date().toISOString(),
          })
          .eq("reference", reference)
          .eq("user_id", user.id);

        return response(
          {
            error:
              "Le montant ou la devise ne correspond pas. Aucun crédit ne sera effectué automatiquement.",
            status: "review",
            reference,
          },
          409,
        );
      }

      const providerTransactionId = String(
        providerData.transaction_id ??
          transaction.provider_transaction_id ??
          "",
      );

      if (!providerTransactionId) {
        return response(
          {
            error:
              "Identifiant de transaction fournisseur manquant. Vérification nécessaire.",
            status: "review",
            reference,
          },
          409,
        );
      }

      // Cette fonction SQL doit rester inaccessible aux utilisateurs.
      const { error: confirmError } = await admin.rpc(
        "confirm_wallet_topup",
        {
          p_reference: reference,
          p_provider_transaction_id: providerTransactionId,
          p_provider_amount_minor: amountMinor,
        },
      );

      if (confirmError) {
        return response(
          {
            error:
              "La confirmation comptable a échoué. Contacte le support avec la référence.",
            status: "review",
            reference,
          },
          409,
        );
      }

      return response({ status: "successful", reference });
    }

    return response({ error: "Action inconnue." }, 400);
  } catch {
    // Ne pas exposer les erreurs internes, les secrets ou les détails serveur.
    return response({ error: "Erreur interne du service de paiement." }, 500);
  }
});
