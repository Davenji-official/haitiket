# Intégration Plop Plop — HAITIKET

## Ce qui est ajouté dans ce sprint
- Migration `0014_wallet_plopplop.sql` : comptes de portefeuille HTG/USD, opérations traçables, solde dérivé des opérations confirmées, protections RLS et idempotence des crédits de recharge.
- Edge Function `plopplop-wallet` : crée les recharges par MonCash/NatCash (page ou USSD) et vérifie leur statut auprès de l'API documentée avant crédit.
- Edge Function `plopplop-webhook` : vérifie `X-Webhook-Signature` HMAC-SHA256 puis revalide l'état avec `api/paiement-verify` avant crédit.
- L'écran Portefeuille permet de créer et vérifier une recharge.

## Secrets — ne jamais les placer dans Flutter, GitHub ou le SQL
Dans Supabase Dashboard → Edge Functions → Secrets, configurer :
- `PLOPPLOP_CLIENT_ID` : Client ID marchand
- `PLOPPLOP_CLIENT_SECRET` : clé privée/hash marchand
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` selon les secrets de projet habituels.

La clé privée a été partagée dans une conversation. Par prudence, régénère/rotates cette clé dans le portail marchand Plop Plop avant la production, puis utilise uniquement la nouvelle clé comme secret Supabase. Ne la recopie pas dans le code.

## Déploiement Supabase
1. Faire une sauvegarde et vérifier quelles migrations ont déjà été appliquées.
2. Appliquer `0014_wallet_plopplop.sql` une seule fois, après `0001`–`0013`. Ne pas exécuter `SQL_bloc_A/B/C` au hasard : ce ne sont pas les migrations numérotées et certaines instructions peuvent se chevaucher.
3. Déployer les fonctions `plopplop-wallet` et `plopplop-webhook`.
4. Dans le portail marchand, configurer l'URL de retour fournie par le compte et le webhook HTTPS : `https://<PROJECT_REF>.supabase.co/functions/v1/plopplop-webhook`. L'URL GitHub Pages n'est pas un endpoint webhook backend fiable et ne doit pas recevoir les notifications serveur.
5. Tester d'abord avec de petits montants et vérifier les transactions côté portail marchand et côté HAITIKET.

## Limites importantes
- La documentation du fournisseur confirme les endpoints de paiement, de vérification, le solde prépayé marchand et le retrait marchand. Le retrait marchand utilise le solde prépayé de l'entreprise : il ne suffit pas à lui seul pour gérer des retraits utilisateur sécurisés. Le retrait utilisateur exige aussi réservation atomique du solde interne, frais affichés, contrôle fraude/limites et rapprochement fournisseur. Il n'est donc pas activé dans l'interface de cette version.
- Les paiements de commande, achats, frais d'abonnement et crédits vendeur/coursier ne sont pas encore tous routés vers le portefeuille. Cette version met en place la base et le flux de recharge ; elle ne doit pas être présentée comme une intégration financière complète avant les tests et la suite des flux.
- Le fournisseur documente des paiements en HTG. La recharge USD est volontairement refusée, pour ne pas appliquer une conversion inventée.
- Le webhook fournisseur est best-effort selon sa documentation ; la vérification serveur reste nécessaire.

## Retraits utilisateur — étape ajoutée
- Edge Function `plopplop-withdraw` : authentifie l'utilisateur, réserve une demande de retrait interne, authentifie le marchand auprès de Plop Plop, signe le jeton HMAC-SHA256 et exécute le retrait MonCash/NatCash. Si le fournisseur ne donne pas de résultat final, l'opération reste en cours et peut être vérifiée via `api/withdraw/marchand/verify`.
- L'interface Portefeuille expose maintenant le formulaire de retrait avec confirmation explicite et contrôle de statut.
- Appliquer aussi `0015_wallet_balance_function_volatility.sql` après vérification des migrations : corrige la volatilité SQL de `my_wallet_v2`, qui crée les comptes de devise à la première lecture.

### Limite de fonds à valider impérativement
Plop Plop retire depuis le solde prépayé du marchand HAITIKET. Ce solde marchand doit être suffisamment approvisionné pour payer les retraits des utilisateurs. Le solde interne d'un utilisateur et le solde prépayé marchand sont deux comptes différents : le retrait doit rester désactivé en production tant que l'approvisionnement, la réconciliation, les réservations atomiques et les tests de refus/timeout ne sont pas validés.
