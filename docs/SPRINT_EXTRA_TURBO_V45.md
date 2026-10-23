# HAITIKET V45 — Journal d'audit administrateur

## Fonction ajoutée

La console administrateur possède un onglet **Journal admin** qui consulte les actions consignées dans `admin_audit_logs`. L'écran propose un filtre local par action, ressource, motif et identifiant, un bouton d'actualisation, la date locale et un maximum de 200 lignes chargées.

## Sécurité

- La lecture passe par la fonction SQL `admin_read_audit_log`.
- La fonction vérifie l'authentification et `admin_unlocked()` côté serveur.
- Les rôles `public` et `anon` n'ont pas le droit d'exécuter la fonction.
- Le résultat est limité à 200 lignes et trié du plus récent au plus ancien.
- La fonctionnalité est en lecture seule : elle ne modifie ni les commandes, ni les portefeuilles, ni les paiements.
- Le journal ne peut montrer que les actions qui ont réellement été consignées par les fonctions existantes; ce n'est pas encore une piste d'audit inviolable ni une preuve de chaque événement applicatif.

## Installation et validation

1. Appliquer `supabase/migrations/0040_admin_audit_log_v45.sql` dans Supabase staging après les migrations précédentes.
2. Vérifier qu'un administrateur authentifié et déverrouillé voit les entrées.
3. Vérifier qu'un utilisateur non-admin ou un administrateur verrouillé reçoit un refus.
4. Lancer `./scripts_validate_v45.sh`, puis `flutter analyze` et `flutter test` dans GitHub Actions.
5. Tester l'onglet sur Web et Android avant déploiement.

## État

- Contrôles statiques : à exécuter avec `scripts_validate_v45.sh`.
- Migration sur Supabase distant : `NOT_RUN`.
- Tests Flutter et builds : `NOT_RUN` dans l'environnement de travail actuel.
- Vérification de permissions staging : `NOT_RUN`.
