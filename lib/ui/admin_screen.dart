import 'package:flutter/material.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'widgets.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 6,
        child: Column(children: [
          const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, labelColor: C.ink, indicatorColor: C.terracotta, tabs: [Tab(text: 'Boutiques'), Tab(text: 'Livreurs'), Tab(text: 'Annonces'), Tab(text: 'Support'), Tab(text: 'Coupons'), Tab(text: 'Paiements')]),
          const Expanded(child: TabBarView(children: [_AdminList('shop'), _AdminList('courier'), _AdminList('listing'), _AdminList('ticket'), _CouponTab(), _AdminList('payment')])),
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

  String title(Map<String, dynamic> r) => switch (widget.kind) {
        'shop' => '${r['name']} · ${r['city'] ?? ''}',
        'courier' => '${r['full_name']} · ${r['transport']} · ${r['zone']}',
        'ticket' => '${r['subject']} — ${r['message']}',
        'payment' => '${r['purpose']} · ${money(r['amount_minor'] as num, 'HTG')}',
        _ => '${r['name']} · ${money(r['price_minor'] as num, r['currency'] as String)}',
      };

  List<Widget> actions(Map<String, dynamic> r) {
    final id = r['id'] as String;
    switch (widget.kind) {
      case 'shop':
        return [
          TextButton(onPressed: () => act(id, 'active'), child: const Text('Activer')),
          TextButton(onPressed: () => act(id, 'suspended', needReason: true), child: const Text('Suspendre')),
        ];
      case 'courier':
        return [
          TextButton(onPressed: () => act(id, 'approved'), child: const Text('Approuver')),
          TextButton(onPressed: () => act(id, 'rejected', needReason: true), child: const Text('Rejeter')),
        ];
      case 'ticket':
        return [TextButton(onPressed: () => reply(id), child: const Text('Répondre'))];
      case 'payment':
        return [];
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
          if (s.hasError) return const Padding(padding: EdgeInsets.all(18), child: EmptyState(title: 'Accès refusé', text: "Ce compte n'a pas le rôle admin."));
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
