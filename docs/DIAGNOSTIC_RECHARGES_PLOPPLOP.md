# Recharge payée chez Plop Plop mais solde resté à zéro — diagnostic et correction

## Comment une recharge est créditée (2 chemins, un seul crédit grâce à l'idempotence)
1. **Retour du client** : après paiement, Plop Plop renvoie le client vers l'adresse de retour ; l'application ouvre le Portefeuille et revérifie la recharge (fonction `plopplop-wallet`, action `check_topup`).
2. **Webhook** : Plop Plop appelle `plopplop-webhook` ; la fonction revérifie auprès de Plop Plop puis crédite.
Si l'un des deux échoue, l'autre rattrape. Si les DEUX échouent (client parti dans l'application MonCash sans revenir + webhook bloqué), la recharge reste « en attente ».

## Causes probables, par ordre
1. **« Verify JWT » activé sur `plopplop-webhook`** : Supabase rejette l'appel de Plop Plop (401) avant même d'exécuter la fonction. Solution : `supabase functions deploy plopplop-webhook --no-verify-jwt`, ou dans le tableau de bord : Edge Functions > plopplop-webhook > réglages > désactiver « Verify JWT ». (Le fichier `supabase/config.toml` fourni le fait automatiquement au déploiement en ligne de commande.)
2. **Secret `PLOPPLOP_CLIENT_SECRET` absent ou différent** de celui du portail Plop Plop : la signature est refusée. Vérifier : `supabase secrets list` ; corriger : `supabase secrets set PLOPPLOP_CLIENT_SECRET=...`.
3. **Adresse de retour mal orthographiée** : le nom du dépôt est `davenji-official` (« official » avec un « a »), pas « officiel ». Adresse correcte à saisir : `https://davenji-official.github.io/haitiket/`. Une faute envoie le client vers une page inexistante : aucune vérification automatique.
4. Montant ou devise différents (recharge placée « à revoir »).

## Réparer la recharge déjà payée
Admin > **Recharges** > bouton « Vérifier et créditer » (ou la flèche de la ligne concernée). Le serveur revérifie chez Plop Plop (statut `ok`, montant, devise) et crédite une seule fois.

## Vérifier que le webhook arrive
Admin > Recharges > « Journal du webhook Plop Plop ». Après un paiement test, une ligne doit apparaître (`credite` ou `pas_encore_paye`). Journal vide = Plop Plop n'atteint pas la fonction (causes 1 ou adresse du webhook). `signature_invalide` = cause 2.

## Adresses à enregistrer chez Plop Plop
* Return URL : `https://davenji-official.github.io/haitiket/`
* Webhook URL : `https://ntroqvxeotifsmdzrwyo.supabase.co/functions/v1/plopplop-webhook`

## USD
Le portefeuille USD suit exactement le même chemin (paiement en HTG converti au taux configuré, puis crédit en USD) : même cause, même réparation.
