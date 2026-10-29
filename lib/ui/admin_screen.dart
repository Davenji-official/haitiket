import 'package:flutter/material.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'admin2.dart';
import 'screens5.dart';
import 'widgets.dart';
import 'screens2.dart';
import 'admin_release_center_v63.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 18,
        child: Column(children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: C.ink,
            indicatorColor: C.terracotta,
            tabs: [Tab(text: 'Tableau'), Tab(text: 'Litiges'), Tab(text: 'Remboursements'), Tab(text: 'Paiements'), Tab(text: 'Signalements'), Tab(text: 'Boutiques'), Tab(text: 'Annonces'), Tab(text: 'Livreurs'), Tab(text: 'Support'), Tab(text: 'Coupons'), Tab(text: 'Comptes'), Tab(text: 'Réglages'), Tab(text: 'Message global'), Tab(text: 'Journal admin'), Tab(text: 'Boutique officielle'), Tab(text: 'KYC'), Tab(text: 'Suppressions'), Tab(text: 'Contrôle lancement')],
          ),
          const Expanded(
            child: TabBarView(children: [
              AdminDashboardTab(),
              _AdminList('dispute'),
              _AdminList('refund'),
              _AdminList('payment'),
              _AdminList('report'),
              _AdminList('shop'),
              _AdminList('listing'),
              _AdminList('courier'),
              _AdminList('ticket'),
              _CouponTab(),
              AdminUsersTab(),
              AdminSettingsTab(),
              AdminAnnouncementsTab(),
              AdminAuditLogTab(),
              const OfficialShopAdminTab(),
              const AdminIdentityVerificationTab(),
              const AdminShopDeletionTab(),
              const AdminReleaseCenterV63(),
            ]),
          ),
        ]),
      );
}

class _AdminList extends StatefulWidget {
  final String kind;
  const _AdminList(this.kind);
  @override
  State<_AdminList> createState() => _AdminListState();
}

class _AdminListState extends State<_AdminList> {
  late Future<List<Map<String, dynamic>>> f = Repo.adminList(widget.kind);
  void reload() => setState(() => f = Repo.adminList(widget.kind));

  Future<void> act(String id, String status, {bool needReason = false}) async {
    var reason = 'decision_admin';
    if (needReason) {
      final c = TextEditingController();
      final r = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Motif obligatoire'),
          content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Expliquez la décision')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Valider')),
          ],
        ),
      );
      if (r == null || r.isEmpty) return;
      reason = r;
    }
    try {
      await Repo.adminSet(widget.kind, id, status, reason);
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> reply(String id) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Réponse au client'),
        content: TextField(controller: c, maxLines: 4, decoration: const InputDecoration(hintText: 'Votre réponse')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Envoyer')),
        ],
      ),
    );
    if (r == null || r.isEmpty) return;
    try {
      await Repo.adminReplyTicket(id, r);
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> custom(String what, Map<String, dynamic> r) async {
    final note = await askText(context, 'Note ou motif', hint: 'Obligatoire');
    if (note == null || note.isEmpty) return;
    final id = r['id'] as String;
    try {
      switch (what) {
        case 'dispute_refund':
          await Repo.adminResolveDispute(id, 'refund', note);
        case 'dispute_no':
          await Repo.adminResolveDispute(id, 'no_refund', note);
        case 'refund_wallet':
          await Repo.adminExecuteWalletRefund(id, note);
        case 'refund_done':
          await Repo.adminMarkRefund(id, true, note);
        case 'refund_fail':
          await Repo.adminMarkRefund(id, false, note);
        case 'report_ok':
          await Repo.adminResolveReport(id, 'actioned', note);
        case 'report_no':
          await Repo.adminResolveReport(id, 'dismissed', note);
        case 'block_product':
          await Repo.adminSet('product', r['target_id'] as String, 'blocked', note);
          await Repo.adminResolveReport(id, 'actioned', note);
      }
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> queueRefund(String id) async {
    try {
      await Repo.adminQueueRefund(id);
      reload();
      if (mounted) toast(context, 'Remboursement ajouté à la file.');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  String kycLabel(String k) => switch (k) {
        'approved' => 'approuvée',
        'pending' => 'dossier envoyé, en attente de décision',
        'needs_changes' => 'à corriger par le vendeur',
        'rejected' => 'refusée',
        _ => 'non envoyée',
      };

  String short(Object? id) => '${id ?? ''}'.length >= 8 ? '${id}'.substring(0, 8) : '${id ?? ''}';

  String title(Map<String, dynamic> r) => switch (widget.kind) {
        'dispute' => 'Commande ${short(r['order_id'])} — ${r['reason']}',
        'refund' => 'Commande ${short(r['order_id'])} · ${money(r['amount_minor'] as num, 'HTG')} — ${r['reason'] ?? ''}',
        'report' => '${r['kind']} ${short(r['target_id'])} — ${r['reason']}',
        'shop' => '${r['name']} · ${r['city'] ?? ''}',
        'courier' => '${r['full_name']} · ${r['transport']} · ${r['zone']}',
        'ticket' => '${r['subject']} — ${r['message']}',
        'payment' => '${r['kind'] ?? r['purpose']} · ${money(r['amount_minor'] as num, '${r['currency'] ?? 'HTG'}')} · ${r['user_name'] ?? ''}',
        _ => '${r['name']} · ${money(r['price_minor'] as num, r['currency'] as String)}',
      };

  List<Widget> actions(Map<String, dynamic> r) {
    final id = r['id'] as String;
    switch (widget.kind) {
      case 'shop':
        final st = '${r['status']}';
        final kyc = '${r['kyc_status'] ?? 'approved'}';
        return [
          if (st != 'active')
            TextButton(
              onPressed: () {
                if (kyc != 'approved') {
                  toast(context, "Impossible d'approuver : l'identité du vendeur n'est pas approuvée (statut : ${kycLabel(kyc)}). Ouvrez l'onglet KYC, traitez son dossier, puis revenez.");
                  return;
                }
                act(id, 'active');
              },
              child: Text(st == 'pending' ? 'Approuver la demande' : 'Réactiver'),
            ),
          if (st == 'pending') TextButton(onPressed: () => act(id, 'closed', needReason: true), child: const Text('Rejeter la demande')),
          if (st == 'active') TextButton(onPressed: () => act(id, 'suspended', needReason: true), child: const Text('Suspendre')),
        ];
      case 'courier':
        return [
          TextButton(onPressed: () => act(id, 'approved'), child: const Text('Approuver')),
          TextButton(onPressed: () => act(id, 'rejected', needReason: true), child: const Text('Rejeter')),
        ];
      case 'ticket':
        return [TextButton(onPressed: () => reply(id), child: const Text('Répondre'))];
      case 'payment':
        return r['status'] == 'refund_required' ? [TextButton(onPressed: () => queueRefund(id), child: const Text('Mettre en remboursement'))] : [];
      case 'dispute':
        return r['status'] != 'open' ? [] : [
          TextButton(onPressed: () => custom('dispute_refund', r), child: const Text('Rembourser le client')),
          TextButton(onPressed: () => custom('dispute_no', r), child: const Text('Refuser le remboursement')),
        ];
      case 'refund':
        return r['status'] != 'to_execute' ? [] : [
          TextButton(onPressed: () => custom('refund_wallet', r), child: const Text('Créditer le portefeuille')),
          TextButton(onPressed: () => custom('refund_done', r), child: const Text('Confirmer remboursement externe')),
          TextButton(onPressed: () => custom('refund_fail', r), child: const Text('Échec')),
        ];
      case 'report':
        return r['status'] != 'open' ? [] : [
          if (r['kind'] == 'product') TextButton(onPressed: () => custom('block_product', r), child: const Text('Bloquer le produit')),
          TextButton(onPressed: () => custom('report_ok', r), child: const Text('Traité')),
          TextButton(onPressed: () => custom('report_no', r), child: const Text('Rejeter')),
        ];
      default:
        return [
          TextButton(onPressed: () => act(id, 'paused'), child: const Text('Rétablir')),
          TextButton(onPressed: () => act(id, 'blocked', needReason: true), child: const Text('Bloquer')),
        ];
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: f,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) {
            return ListView(padding: const EdgeInsets.all(18), children: [
              EmptyState(title: 'Chargement impossible', text: Repo.err(s.error!)),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: reload, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
            ]);
          }
          final items = s.data ?? [];
          if (items.isEmpty) return const Padding(padding: EdgeInsets.all(18), child: EmptyState(title: 'Rien à traiter', text: 'Aucun élément pour le moment.'));
          return ListView(padding: const EdgeInsets.all(14), children: [
            for (final r in items)
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title(r), style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink, fontSize: 16)),
                    Text('Statut : ${r['status']}', style: const TextStyle(color: C.terracotta, fontWeight: FontWeight.w700)),
                    if (widget.kind == 'shop') ...[
                      Text('Propriétaire : ${r['owner_name'] ?? '—'}${r['owner_phone'] == null ? '' : ' · ${r['owner_phone']}'}', style: const TextStyle(color: C.muted)),
                      Text('Identité (KYC) : ${kycLabel('${r['kyc_status'] ?? 'none'}')}', style: TextStyle(fontWeight: FontWeight.w700, color: '${r['kyc_status']}' == 'approved' ? C.green : C.terracotta)),
                    ],
                    if (widget.kind == 'payment') Text('Statut : ${r['status']} · ${r['provider'] ?? ''} · ${r['reference'] ?? ''}', style: const TextStyle(color: C.muted, fontSize: 12)),
                    Wrap(children: actions(r)),
                  ]),
                ),
              ),
          ]);
        },
      );
}


class _CouponTab extends StatefulWidget {
  const _CouponTab();
  @override
  State<_CouponTab> createState() => _CouponTabState();
}

class _CouponTabState extends State<_CouponTab> {
  late Future<List<Map<String, dynamic>>> f = Repo.adminCoupons();
  void reload() => setState(() => f = Repo.adminCoupons());

  Future<void> create() async {
    final code = TextEditingController(), value = TextEditingController(), min = TextEditingController(), uses = TextEditingController(), days = TextEditingController();
    String kind = 'percent';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          title: const Text('Nouveau coupon'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Field(code, 'Code (ex. BIENVENUE10)'),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [DropdownMenuItem(value: 'percent', child: Text('Pourcentage')), DropdownMenuItem(value: 'fixed', child: Text('Montant fixe (HTG)'))],
                onChanged: (v) => set(() => kind = v ?? 'percent'),
              ),
              const SizedBox(height: 12),
              Field(value, kind == 'percent' ? 'Pourcentage (1 à 100)' : 'Montant en HTG', type: TextInputType.number),
              Field(min, 'Achat minimum en HTG (facultatif)', type: TextInputType.number),
              Field(uses, "Nombre d'utilisations max (facultatif)", type: TextInputType.number),
              Field(days, 'Durée de validité en jours (facultatif)', type: TextInputType.number),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(value.text.replaceAll(',', '.'));
    if (v == null || v <= 0) return toast(context, 'Valeur invalide.');
    try {
      await Repo.adminCreateCoupon(code.text.trim(), kind, kind == 'percent' ? v.round() : (v * 100).round(), ((double.tryParse(min.text.replaceAll(',', '.')) ?? 0) * 100).round(), int.tryParse(uses.text), int.tryParse(days.text) ?? 0);
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
        FilledButton.icon(onPressed: create, icon: const Icon(Icons.add), label: const Text('Créer un coupon')),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return const EmptyState(title: 'Accès refusé', text: "Ce compte n'a pas le rôle admin.");
            final items = s.data ?? [];
            if (items.isEmpty) return const EmptyState(title: 'Aucun coupon', text: 'Créez votre premier code promo.');
            return Column(children: [
              for (final c in items)
                Card(
                  color: Colors.white,
                  child: ListTile(
                    title: Text('${c['code']} · ${c['kind'] == 'percent' ? '${c['value']} %' : money(c['value'] as num, 'HTG')}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('Utilisé ${c['used_count']}${c['max_uses'] == null ? '' : ' / ${c['max_uses']}'} fois'),
                    trailing: Switch(
                      value: c['active'] == true,
                      onChanged: (v) async {
                        try {
                          await Repo.adminSetCouponActive(c['id'] as String, v);
                          reload();
                        } catch (e) {
                          if (context.mounted) toast(context, Repo.err(e));
                        }
                      },
                    ),
                  ),
                ),
            ]);
          },
        ),
      ]);
}


/// Gestion de la boutique HAITIKET officielle : aucun abonnement vendeur n'est exigé.
class OfficialShopAdminTab extends StatefulWidget {
  const OfficialShopAdminTab({super.key});
  @override
  State<OfficialShopAdminTab> createState() => _OfficialShopAdminTabState();
}

class _OfficialShopAdminTabState extends State<OfficialShopAdminTab> {
  late Future<Map<String, dynamic>?> future = Repo.adminOfficialShop();
  final name = TextEditingController(text: 'HAITIKET Official Store');
  final city = TextEditingController(text: 'Port-au-Prince');
  final slogan = TextEditingController(text: 'La boutique officielle HAITIKET');
  bool busy = false;
  int panelRevision = 0;

  // Recrée le panneau de gestion après l'enregistrement pour recharger ses listes.
  void reload() => setState(() {
        future = Repo.adminOfficialShop();
        panelRevision++;
      });

  Future<void> save() async {
    if (name.text.trim().length < 2) return toast(context, 'Le nom de la boutique est requis.');
    setState(() => busy = true);
    try {
      await Repo.adminSaveOfficialShop(name: name.text.trim(), city: city.text.trim(), slogan: slogan.text.trim());
      if (mounted) toast(context, 'Boutique officielle enregistrée. Les produits seront publiés dans Marketplace.');
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() { name.dispose(); city.dispose(); slogan.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: future,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return ListView(padding: const EdgeInsets.all(18), children: [ErrorState(snap.error)]);
      final shop = snap.data;
      if (shop != null) {
        name.text = '${shop['name'] ?? ''}';
        city.text = '${shop['city'] ?? ''}';
        slogan.text = '${shop['slogan'] ?? ''}';
      }
      return ListView(padding: const EdgeInsets.all(18), children: [
        const Text('Boutique officielle HAITIKET', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('Une boutique contrôlée par la plateforme, sans abonnement supplémentaire. Ses produits apparaissent dans Marketplace avec le badge officiel. Les produits Bazar restent dans leur section.', style: TextStyle(height: 1.45)),
        const SizedBox(height: 14),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(20)), child: Row(children: [const Icon(Icons.verified, color: C.green, size: 30), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Badge officiel HAITIKET', style: TextStyle(fontWeight: FontWeight.w900)), Text(shop == null ? 'Pas encore créée' : 'Active · ${shop['status']} · Abonnement exempté')]))])),
        const SizedBox(height: 12),
        TextField(controller: name, maxLength: 80, decoration: const InputDecoration(labelText: 'Nom public de la boutique')),
        TextField(controller: city, decoration: const InputDecoration(labelText: 'Ville')),
        TextField(controller: slogan, maxLength: 80, decoration: const InputDecoration(labelText: 'Slogan')),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: busy ? null : save, icon: const Icon(Icons.save_outlined), label: Text(busy ? 'Enregistrement…' : shop == null ? 'Créer la boutique officielle' : 'Enregistrer les paramètres')),
        if (shop != null) ...[
          const SizedBox(height: 20),
          const Divider(),
          const Text('Gestion complète de la boutique', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ShopPanel(shop, key: ValueKey('official-shop-${shop['id']}-$panelRevision')),
        ],
      ]);
    },
  );
}
