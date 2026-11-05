# Activer les notifications push (une seule fois)

1. console.firebase.google.com → créer un projet « HAITIKET » → ajouter une application **Android** avec l'identifiant `com.haitiket.haitiket`.
2. Paramètres du projet → « Vos applications » : notez **API Key**, **App ID**, **Sender ID (numéro du projet)**, **Project ID**.
3. GitHub → Settings → Secrets → Actions : créez `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID`.
4. Firebase → Paramètres → Comptes de service → « Générer une nouvelle clé privée » (fichier JSON).
5. Supabase : `supabase secrets set FCM_SERVICE_ACCOUNT="$(cat cle.json)"` et `supabase secrets set PUSH_WEBHOOK_SECRET=une_valeur_longue_et_secrete`.
6. `supabase functions deploy send-push --no-verify-jwt`
7. Supabase → Database → Webhooks → Create : table `public.notifications`, événement **Insert**, type HTTP Request (POST) vers
   `https://<projet>.supabase.co/functions/v1/send-push`, en-tête `x-webhook-secret: <la valeur de l'étape 5>`.
8. Relancer le workflow : installer l'APK, se connecter, accepter la permission de notification, puis tester par Admin → Diffusion.

Facultatif : secrets `MAP_TILE_URL` (ex. `https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=...`) et `ROUTE_BASE_URL` pour un fournisseur de cartes/itinéraires sous contrat.
iOS : nécessite un compte Apple Developer, un Mac/service de build et une clé APNs ajoutée dans Firebase (non couverte ici).
