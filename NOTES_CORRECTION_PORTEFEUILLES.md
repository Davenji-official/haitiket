# Correction des portefeuilles USD/HTG

## Problèmes corrigés dans cette version
- La migration 0016 bloquait encore toute recharge USD inférieure à 20 USD dans PostgreSQL, même si l'Edge Function acceptait 1 USD. La migration 0018 corrige ce contrôle à 1 USD (100 centimes) pour USD, tout en conservant le minimum de 20 HTG pour HTG.
- Le taux de recharge et le taux de retrait sont maintenant distincts dans le panneau admin : `usd_htg_topup_rate` et `usd_htg_withdraw_rate`.
- `usd_htg_rate` reste un taux de secours pour compatibilité avec les anciennes configurations et les frais Bazar/boutique.
- Le texte de confirmation de retrait affiche désormais la devise sélectionnée au lieu de présenter systématiquement le montant comme HTG.
- L'erreur SQL lors de la création d'une recharge est rendue plus précise pour faciliter le diagnostic.

## Déploiement
1. Sauvegarde le projet actuel.
2. Ajoute les fichiers du ZIP à GitHub sans supprimer les autres fichiers.
3. Dans Supabase SQL Editor, exécute une seule fois `supabase/migrations/0018_wallet_usd_rates_and_minimum.sql`, après les migrations 0016 et 0017 déjà exécutées. Ne réexécute pas 0016/0017 si elles ont déjà réussi.
4. Redéploie les Edge Functions `plopplop-wallet` et `plopplop-withdraw` depuis les nouveaux fichiers.
5. Reconstruis l'application Flutter.
6. Dans l'administration, renseigne un taux positif pour les recharges USD et un autre pour les retraits USD. Si un taux dédié est vide, le système retombe sur `usd_htg_rate`.
7. Teste d'abord sans argent réel.

## Limites importantes
- Cette correction n'atteste pas que les retraits ou recharges ont été testés auprès du fournisseur en production.
- Le minimum réel du fournisseur, ses frais et ses règles doivent être vérifiés. Un montant USD très petit peut être rejeté si son équivalent en HTG est inférieur au minimum accepté par le fournisseur.
- N'exécute aucune recharge/retrait réel avant de vérifier les journaux et le statut fournisseur.
