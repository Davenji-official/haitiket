# HAITIKET V48 — Boutique officielle de la plateforme

## Fonctionnalités ajoutées
- Onglet d’administration « Boutique officielle » : création et modification du nom, de la ville et du slogan.
- Boutique officielle de type `platform`, active, exemptée d’abonnement vendeur et protégée par `admin_unlocked()` côté serveur.
- Badge « Boutique officielle HAITIKET » sur les cartes de ses produits Marketplace.
- La gestion des produits réutilise le panneau vendeur existant (catalogue, stock, variantes, médias, commandes et personnalisation).
- Les produits utilisent `source=marketplace` : ils apparaissent dans la Marketplace, pas dans Bazar.
- Journalisation des créations et mises à jour de la boutique officielle.

## Migration
Appliquer `supabase/migrations/0042_official_platform_shop_v48.sql` en staging avant la production.

## À vérifier en staging
- Admin verrouillé/refusé, admin déverrouillé/autorisé.
- Création idempotente (une seule boutique officielle).
- Publication d’un produit officiel dans Marketplace avec badge.
- Pas d’abonnement exigé même si `enforce_shop_plan=true`.
- Branding et permissions produits.
- Aucun mélange entre Marketplace et Bazar.

Les contrôles statiques ne remplacent pas les tests Flutter, la migration PostgreSQL et les essais sur Supabase réel.
