import 'package:flutter/material.dart';
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
    ['bazar_fee_usd', 'Frais annonce Bazar (USD / 14 jours)', 'Ex. 2'],
    ['shop_fee_usd', 'Abonnement boutique pro (USD / 30 jours)', 'Ex. 20'],
    ['delivery_flat_minor', 'Frais de livraison forfaitaires (centimes de HTG)', 'Ex. 5000 = 50 HTG. Sans valeur, la livraison reste indisponible.'],
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
      await Repo.adminSetUserSuspended(u['id'] as String, suspend, reason);
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
                    trailing: TextButton(onPressed: () => toggle(u), child: Text(u['suspended'] == true ? 'Réactiver' : 'Suspendre')),
                  ),
                ),
            ]);
          },
        ),
      ]);
}
