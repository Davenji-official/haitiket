# Plan de vérification manuel — V12 / V9.2

À exécuter sur un environnement Supabase de test avec de vrais comptes de test approuvés (aucune donnée financière).

1. Coursier non approuvé : `list_open_jobs()` et `accept_job()` doivent être refusés.
2. Coursier approuvé mais indisponible : aucune mission proposée; acceptation refusée.
3. Coursier sans GPS, GPS invalide ou GPS datant de plus de 3 minutes : aucune mission proposée et acceptation refusée.
4. Boutique sans coordonnées ou inactive : sa mission n'est pas proposée et ne peut pas être acceptée.
5. Boutique à plus de 25 km : mission non proposée et acceptation refusée.
6. Deux coursiers acceptent la même mission simultanément : une seule transaction doit réussir; l'autre doit recevoir « Mission déjà prise ou indisponible ».
7. Un coursier tente d'accepter deux missions simultanément alors qu'il en possède déjà deux actives : une seule acceptation supplémentaire doit réussir; il ne doit jamais dépasser trois missions actives.
8. Un utilisateur non propriétaire de mission tente un SELECT direct sur `delivery_jobs` : aucune ligne ne doit lui être exposée par RLS.
9. Confirmer que l'écran actif rafraîchit les propositions environ toutes les 15 secondes; l'application en arrière-plan n'a pas de promesse de push.

Consigner la date, l'identifiant de test, le résultat et toute erreur. Ne pas tester des paiements ou soldes réels dans ce plan.
