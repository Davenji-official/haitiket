import 'package:flutter/material.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'widgets.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(children: [
          const TabBar(labelColor: C.ink, indicatorColor: C.terracotta, tabs: [Tab(text: 'Boutiques'), Tab(text: 'Livreurs'), Tab(text: 'Annonces')]),
          const Expanded(child: TabBarView(children: [_AdminList('shop'), _AdminList('courier'), _AdminList('listing')])),
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

  String title(Map<String, dynamic> r) => switch (widget.kind) {
        'shop' => '${r['name']} · ${r['city'] ?? ''}',
        'courier' => '${r['full_name']} · ${r['transport']} · ${r['zone']}',
        _ => '${r['title']} · ${money(r['price_minor'] as num, r['currency'] as String)}',
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
      default:
        return [
          TextButton(onPressed: () => act(id, 'published'), child: const Text('Publier')),
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
