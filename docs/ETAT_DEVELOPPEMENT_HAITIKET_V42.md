# État de développement HAITIKET — V42

## Ajout réel dans le dépôt

La CI est renforcée contre deux risques de publication visuelle : logos de secours transparents de 1×1 pixel et génération d'icônes qui échoue sans faire échouer le job. Un validateur commun contrôle les logos et les 14 fichiers de mascottes avant les builds Web et Android.

## Preuves locales

- `./scripts_validate_v42.sh` exécuté avec succès.
- Les contrôles statiques hérités V25–V41 ont passé.
- Le validateur a reconnu les 2 PNG et les 14 WebP du dossier de ressources.
- L'archive V42 doit encore être contrôlée après création.

## Statut non confirmé

| Élément | Statut |
|---|---|
| Contrôles statiques locaux V25–V42 | PASS |
| Compilation Flutter Web | NOT_RUN localement |
| Compilation APK Android | NOT_RUN localement |
| Exécution des tests Flutter | NOT_RUN localement |
| Workflow GitHub distant | NOT_CONFIRMED |
| Base Supabase de staging et migrations appliquées | NOT_CONFIRMED |
| Paiements et retraits Plop Plop réels | NOT_RUN |
| Recette bout-en-bout commande, livraison, litige et remboursement | NOT_RUN |

La validation locale ne prouve ni que la production est déployée, ni que les flux financiers fonctionnent réellement. Les variables/secrets GitHub et l'environnement de staging doivent être vérifiés par une personne autorisée.
