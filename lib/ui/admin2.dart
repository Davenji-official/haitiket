import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'screens5.dart';
import 'widgets.dart';
import 'mascot.dart';

class AdminDashboardTab extends StatefulWidget {
  const AdminDashboardTab({super.key});
  @override
  State<AdminDashboardTab> createState() => _DashState();
}

class _DashState extends State<AdminDashboardTab> {
  late Future<Map<String, dynamic>> f = Repo.adminDashboard();

  String _csvCell(Object? value) {
    final raw = '${value ?? ''}';
    return '"${raw.replaceAll('"', '""').replaceAll('\r', ' ').replaceAll('\n', ' ')}"';
  }

  Future<void> exportDashboardCsv(Map<String, dynamic> data) async {
    final rows = <List<String>>[
      ['Rapport', 'Statistiques HAITIKET'],
      ['Généré le (UTC)', DateTime.now().toUtc().toIso8601String()],
      ['Indicateur', 'Valeur'],
    ];
    for (final entry in data.entries) {
      if (entry.value is Map || entry.value is List) continue;
      rows.add([auditLabel(entry.key), '${entry.value ?? ''}']);
    }
    final csv = rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
    await Clipboard.setData(ClipboardData(text: '\uFEFF$csv'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV copié. Collez-le dans Excel, Google Sheets ou un fichier .csv.')),
    );
  }

  String auditLabel(String key) {
    const labels = <String, String>{
      'generated_at': 'Généré le', 'status': 'Statut', 'issue_count': 'Anomalies comptables',
      'warning_count': 'Alertes opérationnelles', 'audit_run_id': 'Identifiant du rapport',
      'mutations_performed': 'Modifications automatiques', 'wallet_by_currency': 'Portefeuilles par devise',
      'wallet_provider_status': 'Transactions par fournisseur et statut',
      'legacy_external_payment_attempts': 'Anciens paiements externes', 'refunds': 'Remboursements',
      'checks': 'Contrôles financiers', 'currency': 'Devise', 'successful_topups_minor': 'Recharges confirmées (unités mineures)',
      'successful_purchases_minor': 'Achats confirmés (unités mineures)', 'successful_withdrawals_minor': 'Retraits confirmés (unités mineures)',
      'successful_refunds_minor': 'Remboursements confirmés (unités mineures)', 'pending_or_processing_count': 'Transactions en attente/en cours',
      'review_count': 'Transactions en revue', 'provider': 'Fournisseur', 'count': 'Nombre',
      'amount_minor': 'Montant (unités mineures)', 'successful_count': 'Paiements externes réussis',
      'pending_count': 'Paiements externes en attente', 'refund_required_count': 'Paiements nécessitant remboursement',
      'legacy_provider_names': 'Fournisseurs historiques', 'waiting_execution': 'Remboursements à exécuter',
      'executed': 'Remboursements exécutés', 'failed': 'Remboursements échoués',
      'wallet_account_currency_mismatch': 'Comptes/devise incohérents', 'duplicate_provider_transaction_ids': 'Identifiants fournisseur en double',
      'successful_topups_missing_provider_id': 'Recharges réussies sans identifiant fournisseur',
      'negative_wallet_accounts': 'Portefeuilles au solde négatif', 'open_disputes': 'Litiges ouverts',
      'pending_over_30_minutes': 'Transactions en attente depuis plus de 30 minutes',
      'review_transactions': 'Transactions nécessitant une revue', 'clean': 'Aucun problème détecté',
      'issues_found': 'Action requise', 'true': 'Oui', 'false': 'Non',
    };
    return labels[key] ?? key.replaceAll('_', ' ');
  }

  String auditText(Object? value, {int depth = 0}) {
    if (value is Map) {
      return value.entries.map((e) => '${List.filled(depth, '  ').join()}${auditLabel(e.key.toString())}:\n${auditText(e.value, depth: depth + 1)}').join('\n');
    }
    if (value is List) {
      if (value.isEmpty) return '${List.filled(depth, '  ').join()}Aucun élément';
      return value.map((item) => '${List.filled(depth, '  ').join()}• ${auditText(item, depth: depth + 1)}').join('\n');
    }
    return '${List.filled(depth, '  ').join()}${value ?? '—'}';
  }

  Widget tile(String label, Object? v, {bool money_ = false, bool alert = false}) {
    final n = (v as num?) ?? 0;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: alert && n > 0 ? const Color(0xFFFFF1EC) : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: alert && n > 0 ? C.terracotta : C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(money_ ? money(n, 'HTG') : '$n', style: TextStyle(fontSize: money_ ? 18 : 28, fontWeight: FontWeight.w900, color: alert && n > 0 ? C.terracotta : C.ink)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: C.muted, fontSize: 13)),
      ]),
    );
  }

  Widget chart(String title, List<MapEntry<String, num>> values) {
    final maxValue = values.fold<num>(1, (m, e) => e.value > m ? e.value : m);
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: C.ink)),
        const SizedBox(height: 12),
        for (final e in values) Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12, color: C.muted))), Text('${e.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.ink))]),
          const SizedBox(height: 4),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LayoutBuilder(builder: (context, constraints) => Container(height: 9, width: constraints.maxWidth, color: C.mint, child: Align(alignment: Alignment.centerLeft, child: Container(width: constraints.maxWidth * (e.value / maxValue).clamp(0, 1).toDouble(), color: C.green))))),
        ])),
      ]),
    );
  }

  Widget group(String title, List<Widget> tiles) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 18, bottom: 8), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.ink))),
        Wrap(spacing: 10, runSpacing: 10, children: tiles),
      ]);

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async {
          setState(() => f = Repo.adminDashboard());
          await f;
        },
        child: FutureBuilder<Map<String, dynamic>>(
          future: f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return ListView(padding: const EdgeInsets.all(18), children: [EmptyState(title: 'Accès refusé', text: Repo.err(s.error!))]);
            final d = s.data!;
            return ListView(padding: const EdgeInsets.all(14), children: [
              const MascotHeader(mascot: Mascot.admin, title: 'Administration', subtitle: 'Chiffres calculés à partir des données réelles (tirez vers le bas pour actualiser).'),
              const SizedBox(height: 8),
              const AdminOrderHistoryPanel(),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Exporter les statistiques (CSV)'),
                onPressed: () async {
                  try {
                    await exportDashboardCsv(d);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Export CSV impossible : ${Repo.err(e)}')),
                    );
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.account_balance_outlined),
                label: const Text('Rapprochement financier Plop Plop'),
                onPressed: () async {
                  try {
                    final audit = await Repo.adminRunFinancialReconciliationV24();
                    if (!context.mounted) return;
                    final entries = auditText(audit);
                    await showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(audit['status'] == 'clean' ? 'Rapprochement terminé : aucune alerte détectée' : 'Rapprochement terminé : action ou vérification nécessaire'),
                        content: SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(entries))),
                        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer'))],
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rapprochement impossible : ${Repo.err(e)}')));
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Audit des garde-fous financiers V26'),
                onPressed: () async {
                  try {
                    final audit = await Repo.adminRunFinancialGuardAuditV26();
                    if (!context.mounted) return;
                    final entries = auditText(audit);
                    await showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(audit['status'] == 'clean' ? 'Garde-fous : aucune anomalie détectée' : 'Garde-fous : vérification nécessaire'),
                        content: SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(entries))),
                        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer'))],
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Audit V26 impossible : ${Repo.err(e)}')));
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Audit du parcours de livraison V27'),
                onPressed: () async {
                  try {
                    final audit = await Repo.adminRunDeliveryFlowAuditV27();
                    if (!context.mounted) return;
                    final entries = auditText(audit);
                    await showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(audit['status'] == 'clean' ? 'Livraison : aucune anomalie détectée' : 'Livraison : vérification nécessaire'),
                        content: SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(entries))),
                        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer'))],
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Audit livraison impossible : ${Repo.err(e)}')));
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Audit commercial boutiques et Bazar V28'),
                onPressed: () async {
                  try {
                    final audit = await Repo.adminRunCommercialFlowAuditV28();
                    if (!context.mounted) return;
                    final entries = auditText(audit);
                    await showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(audit['status'] == 'clean' ? 'Commerce : aucune anomalie détectée' : 'Commerce : vérification nécessaire'),
                        content: SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(entries))),
                        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer'))],
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Audit commercial impossible : ${Repo.err(e)}')));
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.rocket_launch_outlined),
                label: const Text('Audit global de préparation au lancement V29'),
                onPressed: () async {
                  try {
                    final audit = await Repo.adminRunLaunchReadinessAuditV29();
                    if (!context.mounted) return;
                    final entries = auditText(audit);
                    await showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(audit['status'] == 'clean' ? 'Audit global : aucun signalement détecté' : audit['status'] == 'warnings' ? 'Audit global : alertes à examiner' : 'Audit global : corrections nécessaires'),
                        content: SizedBox(width: 560, child: SingleChildScrollView(child: SelectableText(entries))),
                        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer'))],
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Audit global V29 impossible : ${Repo.err(e)}')));
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Lancer l’audit des portefeuilles'),
                onPressed: () async {
                  try {
                    final audit = await Repo.adminRunWalletIntegrityAuditV21();
                    if (!context.mounted) return;
                    final entries = audit.entries.map((e) => '${e.key} : ${e.value}').join('\n');
                    await showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(audit['status'] == 'clean' ? 'Audit terminé : aucun écart détecté' : 'Audit terminé : vérification nécessaire'),
                        content: SingleChildScrollView(child: SelectableText(entries)),
                        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer'))],
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Audit impossible : ${Repo.err(e)}')));
                  }
                },
              ),
              group('À traiter', [
                tile('Litiges ouverts', d['disputes_open'], alert: true),
                tile('Remboursements à exécuter', d['refunds_to_execute'], alert: true),
                tile('Paiements tardifs sans stock', d['payments_refund_required'], alert: true),
                tile('Signalements ouverts', d['reports_open'], alert: true),
                tile('Tickets support', d['tickets_open'], alert: true),
                tile('Boutiques à vérifier', d['shops_pending'], alert: true),
              ]),
              group('Commandes', [
                tile('Commandes au total', d['orders_total']),
                tile('En attente de paiement', d['orders_pending_payment']),
                tile('Payées', d['orders_paid']),
                tile('Livrées', d['orders_delivered']),
                tile('Annulées / remboursées', d['orders_cancelled']),
              ]),
              chart('Diagramme des commandes', [
                MapEntry('En attente de paiement', (d['orders_pending_payment'] as num?) ?? 0),
                MapEntry('Payées', (d['orders_paid'] as num?) ?? 0),
                MapEntry('Livrées', (d['orders_delivered'] as num?) ?? 0),
                MapEntry('Annulées / remboursées', (d['orders_cancelled'] as num?) ?? 0),
              ]),
              group('Argent', [
                tile('Volume encaissé', d['gmv_minor'], money_: true),
                tile('Commissions (net)', d['commission_minor'], money_: true),
                tile('Frais Bazar et abonnements', d['fees_minor'], money_: true),
                tile('Paiements en cours', d['payments_pending']),
                tile('Paiements échoués', d['payments_failed']),
              ]),
              group('Boutiques et Bazar', [
                tile('Boutiques pro actives', d['shops_active']),
                tile('Annonces Bazar actives', d['bazar_active']),
                tile('Utilisateurs', d['users_total']),
              ]),
              group('Livraison', [
                tile('Livreurs approuvés', d['couriers_approved']),
                tile('Livreurs disponibles', d['couriers_available']),
                tile('Missions ouvertes', d['jobs_open']),
                tile('Missions en cours', d['jobs_active']),
              ]),
              const SizedBox(height: 30),
            ]);
          },
        ),
      );
}

class AdminSettingsTab extends StatefulWidget {
  const AdminSettingsTab({super.key});
  @override
  State<AdminSettingsTab> createState() => _SettingsState();
}

class _SettingsState extends State<AdminSettingsTab> {
  late Future<Map<String, String>> f = Repo.adminSettings();
  static const defs = [
    ['usd_htg_rate', 'Taux USD → HTG général', 'Taux de secours pour les frais Bazar/boutique et les anciennes configurations. Ex. 131.5'],
    ['usd_htg_topup_rate', 'Taux USD → HTG pour les recharges', 'Taux appliqué quand un utilisateur recharge son portefeuille USD en payant en HTG. Ex. 131.5'],
    ['usd_htg_withdraw_rate', 'Taux USD → HTG pour les retraits', 'Taux appliqué quand un utilisateur retire des USD vers MonCash/NatCash en HTG. Peut être différent du taux de recharge. Ex. 128.0'],
    ['shop_fee_usd', 'Abonnement boutique pro (USD / 30 jours)', 'Tarif par défaut : 20 USD. Le paiement doit être confirmé côté serveur avant activation.'],
    ['shop_fee_yearly_usd', 'Abonnement boutique pro (USD / 365 jours)', 'Tarif par défaut : 200 USD. Le paiement doit être confirmé côté serveur avant activation.'],
    ['bazar_fee_usd', 'Frais de publication Bazar (USD / 14 jours)', 'Tarif par défaut : 2 USD. Le paiement doit être confirmé côté serveur avant publication.'],
    ['payment_provider', 'Prestataire de paiement sélectionné', 'Plop Plop sert aux mouvements externes de recharge/retrait. Les commandes, abonnements, annonces Bazar et ajustements de livraison utilisent les portefeuilles internes selon les fonctions disponibles.'],
    ['delivery_immediate_sla_minutes', 'Délai cible livraison immédiate (minutes)', 'Valeur demandée : 45. Afficher comme objectif, jamais comme garantie de trafic.'],
    ['delivery_traffic_extension_options', 'Extensions trafic autorisées (minutes)', 'Ex. 120,240 pour proposer 2 h ou 4 h, avec motif et horodatage.'],
    ['delivery_offer_expiry_minutes', 'Expiration des offres de livraison (minutes)', 'Durée pendant laquelle le client peut comparer les offres des livreurs.'],
    ['delivery_flat_minor', 'Frais de livraison forfaitaires (centimes de HTG)', 'Utilisé uniquement si la politique de tarification forfaitaire est activée. Sinon, les offres réelles des livreurs doivent être choisies.'],
    ['commission_bps', 'Commission (points de base)', '200 = 2 %. Appliquée aux nouvelles commandes.'],
    ['reservation_minutes', 'Durée de réservation du stock (minutes)', 'Ex. 30'],
    ['enforce_shop_plan', "Exiger l'abonnement pour afficher les boutiques", 'true ou false. À activer quand les paiements fonctionnent.'],
    ['referral_reward_minor', 'Récompense de parrainage (centimes de HTG)', 'Sans valeur, aucune récompense n\'est créée.'],
  ];

  Future<void> edit(String key, String label) async {
    final v = await askText(context, label, hint: 'Nouvelle valeur');
    if (v == null || v.isEmpty) return;
    try {
      await Repo.adminSetSetting(key, v);
      setState(() => f = Repo.adminSettings());
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, String>>(
        future: f,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) return ListView(padding: const EdgeInsets.all(18), children: [EmptyState(title: 'Accès refusé', text: Repo.err(s.error!))]);
          final m = s.data!;
          return ListView(padding: const EdgeInsets.all(14), children: [
            for (final d in defs)
              Card(
                color: Colors.white,
                child: ListTile(
                  title: Text(d[1], style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${d[2]}\nValeur actuelle : ${m[d[0]] ?? 'non définie'}'),
                  isThreeLine: true,
                  trailing: IconButton(icon: const Icon(Icons.edit_outlined, color: C.green), onPressed: () => edit(d[0], d[1])),
                ),
              ),
          ]);
        },
      );
}

class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({super.key});
  @override
  State<AdminUsersTab> createState() => _UsersState();
}

class _UsersState extends State<AdminUsersTab> {
  final q = TextEditingController();
  late Future<List<Map<String, dynamic>>> f = Repo.adminSearchUsers('');

  Future<void> toggle(Map<String, dynamic> u) async {
    final suspend = u['suspended'] != true;
    String reason = '';
    if (suspend) {
      final r = await askText(context, 'Motif de la suspension', hint: 'Obligatoire');
      if (r == null || r.isEmpty) return;
      reason = r;
    }
    try {
      await Repo.adminManageUser(u['id'] as String, suspend ? 'ban' : 'unban', reason.isEmpty ? 'Rétablissement administratif' : reason);
      setState(() => f = Repo.adminSearchUsers(q.text.trim()));
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
        TextField(controller: q, onSubmitted: (v) => setState(() => f = Repo.adminSearchUsers(v.trim())), decoration: InputDecoration(labelText: 'Rechercher par e-mail ou nom', suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => f = Repo.adminSearchUsers(q.text.trim()))))),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return EmptyState(title: 'Accès refusé', text: Repo.err(s.error!));
            final l = s.data ?? [];
            if (l.isEmpty) return const EmptyState(title: 'Aucun compte', text: 'Aucun résultat.');
            return Column(children: [
              for (final u in l)
                Card(
                  color: u['suspended'] == true ? const Color(0xFFFFF1EC) : Colors.white,
                  child: ListTile(
                    title: Text('${u['display_name'] ?? 'Sans nom'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${u['email'] ?? ''}${u['suspended'] == true ? '\nSUSPENDU' : ''}'),
                    trailing: Wrap(spacing: 4, children: [TextButton(onPressed: () => toggle(u), child: Text(u['suspended'] == true ? 'Réactiver' : 'Bannir')), IconButton(tooltip: 'Supprimer logiquement', icon: const Icon(Icons.person_off_outlined, color: Colors.redAccent), onPressed: () async { final reason = await askText(context, 'Suppression logique du compte', hint: 'Motif obligatoire'); if (reason == null || reason.trim().length < 3) return; final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Confirmer la suppression logique ?'), content: const Text('Le compte sera bloqué; les commandes et preuves d’audit seront conservées.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Confirmer'))])); if (ok != true) return; try { await Repo.adminManageUser(u['id'] as String, 'soft_delete', reason); setState(() => f = Repo.adminSearchUsers(q.text.trim())); } catch (e) { if (mounted) toast(context, Repo.err(e)); } })]),
                  ),
                ),
            ]);
          },
        ),
      ]);
}

/// Publication d'un message global visible sur l'écran de tous les utilisateurs.
class AdminAnnouncementsTab extends StatefulWidget {
  const AdminAnnouncementsTab({super.key});
  @override
  State<AdminAnnouncementsTab> createState() => _AnnouncementsState();
}

class _AnnouncementsState extends State<AdminAnnouncementsTab> {
  final title = TextEditingController();
  final body = TextEditingController();
  String severity = 'info';
  late Future<List<Map<String, dynamic>>> f = Repo.adminAnnouncements();
  bool busy = false;

  @override
  void dispose() { title.dispose(); body.dispose(); super.dispose(); }

  Future<void> publish() async {
    if (title.text.trim().length < 2 || body.text.trim().length < 2) {
      toast(context, 'Ajoutez un titre et un message.'); return;
    }
    setState(() => busy = true);
    try {
      await Repo.adminPublishAnnouncement(title.text.trim(), body.text.trim(), severity);
      title.clear(); body.clear();
      setState(() => f = Repo.adminAnnouncements());
      if (mounted) toast(context, 'Message global publié.');
    } catch (e) { if (mounted) toast(context, Repo.err(e)); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> deactivate(String id) async {
    try {
      await Repo.adminDeactivateAnnouncement(id);
      setState(() => f = Repo.adminAnnouncements());
      if (mounted) toast(context, 'Message désactivé.');
    } catch (e) { if (mounted) toast(context, Repo.err(e)); }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
    const Text('Message diffusé à tous les utilisateurs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.ink)),
    const SizedBox(height: 6),
    const Text('Une seule annonce globale est active à la fois. La publication remplace l’annonce précédente. Les utilisateurs doivent être en ligne ou rouvrir l’application pour voir la mise à jour.', style: TextStyle(color: C.muted, height: 1.4)),
    const SizedBox(height: 14),
    TextField(controller: title, maxLength: 100, decoration: const InputDecoration(labelText: 'Titre', hintText: 'Ex. Maintenance programmée')),
    const SizedBox(height: 10),
    TextField(controller: body, maxLength: 1200, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Message', hintText: 'Écrivez le message à afficher sur l’écran des utilisateurs')),
    const SizedBox(height: 10),
    DropdownButtonFormField<String>(value: severity, decoration: const InputDecoration(labelText: 'Type de message'), items: const [
      DropdownMenuItem(value: 'info', child: Text('Information')),
      DropdownMenuItem(value: 'success', child: Text('Bonne nouvelle')),
      DropdownMenuItem(value: 'warning', child: Text('Avertissement')),
      DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
    ], onChanged: busy ? null : (v) { if (v != null) setState(() => severity = v); }),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: busy ? null : publish, icon: const Icon(Icons.campaign_outlined), label: Text(busy ? 'Publication…' : 'Publier pour tous')),
    const SizedBox(height: 24),
    const Text('Historique des messages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: C.ink)),
    FutureBuilder<List<Map<String, dynamic>>>(future: f, builder: (_, s) {
      if (s.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
      if (s.hasError) return Padding(padding: const EdgeInsets.all(8), child: Text('Historique indisponible : ${Repo.err(s.error!)}'));
      final rows = s.data ?? const [];
      if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('Aucun message publié.'));
      return Column(children: [for (final a in rows) Card(color: Colors.white, child: ListTile(
        leading: Icon(a['active'] == true ? Icons.campaign : Icons.history, color: a['active'] == true ? C.terracotta : C.muted),
        title: Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${a['body']}\nStatut : ${a['active'] == true ? 'ACTIF' : 'Inactif'} · Type : ${a['severity']}'),
        isThreeLine: true,
        trailing: a['active'] == true ? IconButton(tooltip: 'Désactiver', onPressed: () => deactivate(a['id'] as String), icon: const Icon(Icons.visibility_off_outlined)) : null,
      ))]);
    }),
  ]);
}


/// Journal consultatif des actions administratives. Les données sont filtrées côté UI
/// après récupération d'un maximum limité côté serveur.
class AdminAuditLogTab extends StatefulWidget {
  const AdminAuditLogTab({super.key});
  @override
  State<AdminAuditLogTab> createState() => _AdminAuditLogTabState();
}

class _AdminAuditLogTabState extends State<AdminAuditLogTab> {
  late Future<List<Map<String, dynamic>>> future = Repo.adminAuditLog();
  final filter = TextEditingController();

  @override
  void dispose() { filter.dispose(); super.dispose(); }

  void reload() => setState(() => future = Repo.adminAuditLog());

  String _csvCell(Object? value) {
    var raw = '${value ?? ''}'.replaceAll('\r', ' ').replaceAll('\n', ' ');
    // Neutralise les formules lors d'une ouverture directe dans un tableur.
    final trimmed = raw.trimLeft();
    if (trimmed.isNotEmpty && '=+-@'.contains(trimmed[0])) raw = "'$raw";
    return '"${raw.replaceAll('"', '""')}"';
  }

  Future<void> exportFilteredCsv(List<Map<String, dynamic>> rows) async {
    final output = <List<String>>[
      ['Rapport', 'Journal des actions administratives HAITIKET'],
      ['Exporté le (UTC)', DateTime.now().toUtc().toIso8601String()],
      ['Périmètre', 'Entrées chargées par le serveur puis filtrées dans cet écran (maximum 200)'],
      ['Date UTC', 'Action', 'Ressource', 'Identifiant ressource', 'Acteur', 'Motif / détail'],
      ...rows.map((row) => <String>[
        '${row['created_at'] ?? ''}',
        '${row['action'] ?? ''}',
        '${row['resource'] ?? ''}',
        '${row['resource_id'] ?? ''}',
        '${row['actor'] ?? ''}',
        '${row['reason'] ?? ''}',
      ]),
    ];
    final csv = output.map((row) => row.map(_csvCell).join(',')).join('\r\n');
    await Clipboard.setData(ClipboardData(text: '\uFEFF$csv'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Export CSV copié : ${rows.length} entrée(s). Collez dans un tableur puis enregistrez en .csv.')),
    );
  }

  String displayDate(Object? value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return '${value ?? 'Date inconnue'}';
    return parsed.toLocal().toString().split('.').first;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return ListView(padding: const EdgeInsets.all(16), children: [
        EmptyState(title: 'Journal indisponible', text: Repo.err(snapshot.error!)),
        FilledButton.icon(onPressed: reload, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
      ]);
      final all = snapshot.data ?? const <Map<String, dynamic>>[];
      final term = filter.text.trim().toLowerCase();
      final rows = all.where((row) => term.isEmpty || [row['action'], row['resource'], row['reason'], row['actor'], row['resource_id']]
        .any((v) => '${v ?? ''}'.toLowerCase().contains(term))).toList();
      return ListView(padding: const EdgeInsets.all(14), children: [
        const Text('Journal des actions administratives', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.ink)),
        const SizedBox(height: 6),
        const Text('Historique en lecture seule des actions consignées par le serveur. Les entrées visibles dépendent des événements effectivement enregistrés.', style: TextStyle(color: C.muted, height: 1.4)),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: TextField(controller: filter, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Filtrer action, ressource, motif ou identifiant', prefixIcon: Icon(Icons.search)))), const SizedBox(width: 8), IconButton(tooltip: 'Actualiser', onPressed: reload, icon: const Icon(Icons.refresh))]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: rows.isEmpty ? null : () async {
            try {
              await exportFilteredCsv(rows);
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export du journal impossible : ${Repo.err(e)}')));
            }
          },
          icon: const Icon(Icons.file_download_outlined),
          label: Text('Exporter les ${rows.length} entrées filtrées (CSV)'),
        ),
        const SizedBox(height: 10),
        Text('${rows.length} entrée(s) affichée(s) · ${all.length} chargée(s), maximum 200', style: const TextStyle(color: C.muted)),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Aucune action ne correspond à ce filtre.')),
        for (final row in rows) Card(color: Colors.white, child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Text('${row['action'] ?? 'Action inconnue'}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink))), Text(displayDate(row['created_at']), style: const TextStyle(fontSize: 12, color: C.muted))]),
          const SizedBox(height: 5),
          Text('Ressource : ${row['resource'] ?? '—'}${row['resource_id'] == null ? '' : ' · ${row['resource_id']}'}', style: const TextStyle(color: C.muted)),
          if ('${row['reason'] ?? ''}'.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Motif / détail : ${row['reason']}', style: const TextStyle(color: C.ink))),
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Acteur : ${row['actor'] ?? '—'}', style: const TextStyle(fontSize: 12, color: C.muted))),
        ]))),
      ]);
    },
  );
}


/// Graphiques historiques chargés depuis une fonction SQL autorisée côté serveur.
/// Les valeurs HTG et USD sont affichées séparément et ne sont jamais additionnées.
class AdminOrderHistoryPanel extends StatefulWidget {
  const AdminOrderHistoryPanel({super.key});
  @override
  State<AdminOrderHistoryPanel> createState() => _AdminOrderHistoryPanelState();
}

class _AdminOrderHistoryPanelState extends State<AdminOrderHistoryPanel> {
  int days = 30;
  String currency = 'ALL';
  late Future<List<Map<String, dynamic>>> future = Repo.adminOrderHistory(days: days, currency: currency);

  void reload() => setState(() => future = Repo.adminOrderHistory(days: days, currency: currency));

  Widget _seriesChart(String title, List<Map<String, dynamic>> rows, String metric) {
    final maxValue = rows.fold<double>(1, (m, row) {
      final value = ((row[metric] as num?) ?? 0).toDouble();
      return value > m ? value : m;
    });
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
        const SizedBox(height: 10),
        for (final row in rows) ...[
          Row(children: [
            SizedBox(width: 48, child: Text('${row['day']}'.toString().substring(5), style: const TextStyle(fontSize: 11, color: C.muted))),
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(5), child: Container(height: 10, color: C.mint, child: Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: ((((row[metric] as num?) ?? 0).toDouble() / maxValue).clamp(0, 1)).toDouble(), child: Container(color: C.green))))),
            const SizedBox(width: 8),
            SizedBox(width: 66, child: Text('${row[metric] ?? 0}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 7),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('Historique des commandes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: C.ink))),
        IconButton(tooltip: 'Actualiser', onPressed: reload, icon: const Icon(Icons.refresh)),
      ]),
      const Text('Commandes et montants encaissés par jour. Les devises restent séparées.', style: TextStyle(color: C.muted, fontSize: 12)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        DropdownButton<int>(value: days, items: const [7, 30, 90].map((d) => DropdownMenuItem(value: d, child: Text('$d jours'))).toList(), onChanged: (v) { if (v != null) setState(() { days = v; future = Repo.adminOrderHistory(days: days, currency: currency); }); }),
        DropdownButton<String>(value: currency, items: const [DropdownMenuItem(value: 'ALL', child: Text('Toutes les devises (séparées)')), DropdownMenuItem(value: 'HTG', child: Text('HTG seulement')), DropdownMenuItem(value: 'USD', child: Text('USD seulement'))], onChanged: (v) { if (v != null) setState(() { currency = v; future = Repo.adminOrderHistory(days: days, currency: currency); }); }),
      ]),
      FutureBuilder<List<Map<String, dynamic>>>(future: future, builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()));
        if (snapshot.hasError) return Padding(padding: const EdgeInsets.all(8), child: Text('Historique indisponible. Vérifiez que la migration V47 a été appliquée : ${Repo.err(snapshot.error!)}', style: const TextStyle(color: C.terracotta)));
        final all = snapshot.data ?? const <Map<String, dynamic>>[];
        if (all.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('Aucune donnée pour cette période.'));
        final currencies = currency == 'ALL' ? const ['HTG', 'USD'] : [currency];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final cur in currencies) ...[
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(cur, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: C.green))),
            _seriesChart('Nombre de commandes — $cur', all.where((row) => row['currency'] == cur).toList(), 'order_count'),
            _seriesChart('Montant des commandes payées (unités mineures) — $cur', all.where((row) => row['currency'] == cur).toList(), 'paid_total_minor'),
          ],
          const SizedBox(height: 6),
          const Text('Les montants sont affichés en unités mineures (centimes) ; ce graphique est un rapport opérationnel, pas un relevé comptable.', style: TextStyle(fontSize: 11, color: C.muted)),
        ]);
      }),
    ]),
  );
}


class AdminIdentityVerificationTab extends StatefulWidget {
  const AdminIdentityVerificationTab({super.key});
  @override
  State<AdminIdentityVerificationTab> createState() => _AdminIdentityVerificationTabState();
}

class _AdminIdentityVerificationTabState extends State<AdminIdentityVerificationTab> {
  late Future<List<Map<String, dynamic>>> f = Repo.adminIdentityVerifications();
  void reload() => setState(() => f = Repo.adminIdentityVerifications());

  Future<void> openDocument(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final url = await Repo.adminSignedKycDocumentUrl(path);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) { if (mounted) toast(context, Repo.err(e)); }
  }

  Future<void> review(Map<String, dynamic> item, String status) async {
    final note = await askText(context, status == 'approved' ? 'Valider le dossier KYC' : 'Motif de décision KYC', hint: 'Motif / commentaire obligatoire');
    if (note == null || note.trim().length < 3) return;
    try { await Repo.adminReviewIdentityVerification(item['id'].toString(), status, note); reload(); }
    catch (e) { if (mounted) toast(context, Repo.err(e)); }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: f, builder: (_, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return Center(child: Text('Accès refusé : ${Repo.err(snap.error!)}'));
      final items = snap.data ?? [];
      if (items.isEmpty) return const EmptyState(title: 'Aucun dossier KYC', text: 'Les nouvelles demandes apparaîtront ici.');
      return ListView(padding: const EdgeInsets.all(12), children: [
        const Text('Dossiers d’identité privés — ouvrir les pièces uniquement pour la vérification nécessaire.', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final item in items) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${item['user_id']} · ${item['status']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('Naissance : ${item['date_of_birth']} · âge calculé : ${item['age_at_submission']} ans'),
          Text('Type : ${item['identity_document_type'] ?? '—'}'),
          if (item['guardian_full_name'] != null) Text('Responsable : ${item['guardian_full_name']} · naissance : ${item['guardian_date_of_birth']}'),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (item['identity_document_path'] != null) OutlinedButton(onPressed: () => openDocument(item['identity_document_path'] as String?), child: const Text('Pièce identité')),
            if (item['birth_certificate_path'] != null) OutlinedButton(onPressed: () => openDocument(item['birth_certificate_path'] as String?), child: const Text('Acte naissance')),
            if (item['guardian_document_path'] != null) OutlinedButton(onPressed: () => openDocument(item['guardian_document_path'] as String?), child: const Text('Pièce responsable')),
            OutlinedButton(onPressed: () => openDocument(item['recent_photo_path'] as String?), child: const Text('Photo récente')),
          ]),
          if (item['status'] == 'pending') Wrap(spacing: 8, children: [FilledButton(onPressed: () => review(item, 'approved'), child: const Text('Approuver')), OutlinedButton(onPressed: () => review(item, 'needs_changes'), child: const Text('Compléter')), TextButton(onPressed: () => review(item, 'rejected'), child: const Text('Refuser'))]),
        ]))),
      ]);
    },
  );
}

class AdminShopDeletionTab extends StatefulWidget {
  const AdminShopDeletionTab({super.key});
  @override
  State<AdminShopDeletionTab> createState() => _AdminShopDeletionTabState();
}

class _AdminShopDeletionTabState extends State<AdminShopDeletionTab> {
  late Future<List<Map<String, dynamic>>> f = Repo.adminPendingShopDeletions();
  void reload() => setState(() => f = Repo.adminPendingShopDeletions());
  Future<void> act(Map<String, dynamic> shop, bool approve) async {
    final reason = await askText(context, approve ? 'Valider la demande de suppression' : 'Refuser la demande', hint: 'Motif obligatoire');
    if (reason == null || reason.trim().length < 3) return;
    try {
      final result = await Repo.adminReviewShopDeletion(shop['id'].toString(), approve, reason);
      if (mounted) toast(context, 'Décision enregistrée · commandes traitées : ${result['cancelled_orders'] ?? 0} · remboursements mis en file : ${result['refunds_queued'] ?? 0}');
      reload();
    } catch (e) { if (mounted) toast(context, Repo.err(e)); }
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(future: f, builder: (_, snap) {
    if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snap.hasError) return Center(child: Text('Accès refusé : ${Repo.err(snap.error!)}'));
    final items = snap.data ?? [];
    if (items.isEmpty) return const EmptyState(title: 'Aucune demande en attente', text: 'Les demandes de suppression seront affichées ici.');
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Text('La validation ne supprime pas immédiatement les données. Délai minimal de 30 jours; les remboursements doivent être confirmés.', style: TextStyle(fontWeight: FontWeight.w700)),
      for (final shop in items) Card(child: ListTile(title: Text('${shop['name']}', style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('Boutique ${shop['id']}\nDemandée : ${shop['deletion_requested_at']}\nSuppression au plus tôt : ${shop['deletion_scheduled_at']}\nStatut : ${shop['deletion_review_status']}'), isThreeLine: true, trailing: Wrap(children: [if (shop['deletion_review_status'] == 'pending_admin') IconButton(tooltip: 'Approuver', icon: const Icon(Icons.check_circle_outline, color: Colors.green), onPressed: () => act(shop, true)), if (shop['deletion_review_status'] == 'pending_admin') IconButton(tooltip: 'Refuser', icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent), onPressed: () => act(shop, false)), if (shop['deletion_review_status'] == 'approved') IconButton(tooltip: 'Finaliser après 30 jours et réconciliation', icon: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent), onPressed: () async { try { await Repo.adminFinalizeShopDeletion(shop['id'].toString()); if (mounted) toast(context, 'Fermeture logique finalisée; historique conservé.'); reload(); } catch (e) { if (mounted) toast(context, Repo.err(e)); } })]))),
    ]);
  });
}
