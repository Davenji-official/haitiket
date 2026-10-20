# Guide — pousser HAITIKET sur GitHub

## Option A — remplacer le contenu du dépôt par le contenu de cette archive

1. Téléchargez puis décompressez l'archive ZIP.
2. Ouvrez votre dépôt GitHub `Davenji-officiel/haitiket` dans le navigateur.
3. Avant remplacement, téléchargez une copie de sauvegarde du dépôt actuel.
4. Pour chaque fichier du projet, utilisez **Add file → Upload files** ou GitHub Desktop/Git si vous en disposez. Sur mobile, le chargement dossier par dossier peut être difficile; GitHub web ne remplace pas toujours proprement des dossiers entiers.
5. Préservez les secrets et paramètres propres au dépôt. Ne téléversez jamais `.env`, une clé `service_role`, un mot de passe ou une clé privée de paiement.
6. Vérifiez que `lib/`, `supabase/`, `.github/`, `pubspec.yaml`, `README.md`, `NOTES_VERSION.md` et ce guide sont à la racine du dépôt (pas dans un sous-dossier `haitiket-main/haitiket-main/`).
7. Ouvrez **Actions** et vérifiez le résultat du workflow. Un workflow vert ne remplace pas les tests de paiement/RLS.

## Fichiers à pousser

- Tout le contenu de `haitiket-main/` à la racine du dépôt.
- En particulier le nouveau `supabase/migrations/0013_catalog_messaging_controls.sql`.
- Les modifications de `lib/ui/product_detail.dart`.
- `README.md`, `NOTES_VERSION.md`, `DEPLOIEMENT_GITHUB.md`.

## Migration Supabase

N'exécutez pas automatiquement tout le dossier SQL si certaines migrations ont déjà été appliquées. Dans Supabase, vérifiez d'abord les migrations existantes et comparez le schéma. Si 0001 à 0012 et les blocs SQL A/B/C requis sont déjà appliqués et validés, exécutez uniquement `0013_catalog_messaging_controls.sql` dans l'éditeur SQL. Si votre base n'est pas à cet état, arrêtez-vous et réconciliez les migrations avant d'exécuter 0013.

Testez d'abord sur un projet Supabase de développement. Vérifiez que les tables `product_variants`, `products`, `notifications`, `conversations` et `messages` existent. Gardez une sauvegarde de la base avant migration.

## Configuration et sécurité

- `lib/config.dart` contient une URL Supabase et une clé publique de client. Les clés publiques peuvent être embarquées, mais toutes les tables doivent être protégées par RLS.
- Ne mettez jamais la clé privée Pay'm Plop Plop ou la clé Supabase `service_role` dans `lib/`, dans GitHub Actions en clair, ou dans une application cliente.
- La clé privée Pay'm partagée précédemment doit être révoquée/renouvelée auprès du fournisseur.
- Les secrets des fonctions Edge doivent être configurés dans Supabase, puis les fonctions déployées et testées avec les webhooks du fournisseur.

## Contrôles après publication

- [ ] `flutter pub get`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] Build Web et Android réussis
- [ ] Migration SQL testée en environnement de développement
- [ ] Connexion/inscription testées
- [ ] Créer, modifier, masquer et supprimer un produit testés
- [ ] Prix/stock/variantes et commandes vérifiés côté serveur
- [ ] Suppression de notification et masquage de conversation vérifiés avec deux comptes
- [ ] Paiements testés en sandbox, webhook signé et traitement idempotent
- [ ] Aucun secret privé présent dans les fichiers suivis par Git
