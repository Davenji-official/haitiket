# HAITIKET V46 — Export CSV du journal administratif

## Changement livré dans le code
- Ajout d'un bouton d'export dans l'onglet « Journal admin ».
- Export des entrées correspondant au filtre courant, avec colonnes date UTC, action, ressource, identifiant ressource, acteur et motif.
- Format CSV UTF-8 avec BOM, lignes CRLF et échappement des guillemets.
- Neutralisation des valeurs commençant par `=`, `+`, `-` ou `@` pour réduire le risque d'injection de formule à l'ouverture dans un tableur.
- Le bouton est désactivé si le filtre ne retourne aucune entrée.
- L'export copie le CSV dans le presse-papiers ; l'administrateur doit ensuite le coller dans un tableur et enregistrer le fichier. Aucun fichier n'est créé directement par l'application.

## Limites et contrôles
- L'export couvre uniquement les entrées chargées par la requête existante puis filtrées dans l'écran, au maximum 200 entrées. Il ne doit pas être présenté comme un export intégral ou paginé de tout l'historique.
- Les droits d'accès restent contrôlés par le RPC de lecture du journal et la console admin déverrouillée.
- `./scripts_validate_v46.sh` vérifie statiquement le contrat d'export et exécute les validateurs précédents.
- Statut `NOT_RUN` : analyse Dart, tests Flutter, compilation Web/Android, tests de copie presse-papiers sur appareils, vérification des permissions réelles en Supabase staging.
