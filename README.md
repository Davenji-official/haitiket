# HAITIKET — projet Flutter + Supabase

HAITIKET est une application de marketplace, Bazar, boutiques, commandes et services de livraison en cours de développement.

## Contenu du dépôt
- `lib/` : application Flutter (Android/Web) et écrans.
- `supabase/migrations/` : schéma SQL et politiques de sécurité/RLS.
- `supabase/functions/` : fonctions Edge de paiement actuellement présentes dans le dépôt.
- `.github/workflows/build.yml` : workflow CI GitHub Actions.
- `DEPLOIEMENT_GITHUB.md` : instructions de publication et vérifications requises.
- `NOTES_VERSION.md` : ce qui a été ajouté dans cette archive et ce qui reste à valider.

## Important
Cette archive est une mise à jour de développement, pas une certification de mise en production. Les paiements réels, webhooks, politiques RLS, migrations et parcours de commande doivent être testés sur un projet Supabase de test avant la production. Ne placez jamais de clé privée de paiement ou de `service_role` dans Flutter/GitHub.

## Flutter
```bash
flutter pub get
flutter analyze
flutter test
flutter build web --release
```
