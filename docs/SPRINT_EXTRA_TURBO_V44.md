# HAITIKET V44 — Export des statistiques d'administration

## Fonction ajoutée

Le tableau de bord d'administration propose **Exporter les statistiques (CSV)**. L'export utilise les indicateurs déjà chargés par `Repo.adminDashboard()`, ajoute un horodatage UTC et copie le CSV dans le presse-papiers pour collage dans Excel, LibreOffice ou Google Sheets.

- Les champs CSV sont échappés (guillemets doublés, retours à la ligne neutralisés).
- Les objets et listes imbriqués sont ignorés pour éviter une représentation ambiguë ; seuls les indicateurs scalaires sont exportés.
- L'export ne crée pas de nouveau point d'accès, ne modifie aucune donnée et ne contourne pas les contrôles d'accès existants au tableau de bord.
- Le CSV est copié dans le presse-papiers, il n'est pas téléchargé automatiquement comme fichier.

## Validation

Le validateur statique `scripts_validate_v44.sh` vérifie la présence du bouton, le branchement des données courantes, l'utilisation du presse-papiers et l'intégration dans le workflow qualité.

**État :** contrôles statiques à exécuter. Les tests Flutter, l'analyse Dart et la compilation Web/Android doivent être exécutés dans CI. L'accès admin et la source des chiffres restent soumis aux règles et à la disponibilité de Supabase. Aucun test de production n'est affirmé ici.
