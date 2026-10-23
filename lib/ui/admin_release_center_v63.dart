import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'widgets.dart';

/// Operational read-only control center. All counts come from the server snapshot.
class AdminReleaseCenterV63 extends StatefulWidget {
  const AdminReleaseCenterV63({super.key});
  @override
  State<AdminReleaseCenterV63> createState() => _AdminReleaseCenterV63State();
}

class _AdminReleaseCenterV63State extends State<AdminReleaseCenterV63> {
  late Future<Map<String, dynamic>> _future = Repo.adminReleaseReadinessV62();
  void _refresh() => setState(() => _future = Repo.adminReleaseReadinessV62());

  String _label(String key) => switch (key) {
    'refunds_unresolved' => 'Remboursements non résolus',
    'refunds_older_than_24h' => 'Remboursements de plus de 24 h',
    'kyc_waiting_review' => 'Dossiers KYC à examiner',
    'shop_deletions_waiting_or_in_cooling_off' => 'Suppressions en attente / délai de 30 jours',
    'approved_shop_deletions_blocked_by_refunds' => 'Suppressions bloquées par remboursement',
    'disputed_orders' => 'Commandes en litige',
    'payment_attempts_refund_required' => 'Paiements à rapprocher pour remboursement',
    _ => key.replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async { _refresh(); await _future; },
    child: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return ListView(padding: const EdgeInsets.all(20), children: [EmptyState(title: 'Centre de contrôle indisponible', text: Repo.err(snap.error!))]);
        final data = snap.data ?? <String, dynamic>{};
        final keys = <String>['refunds_unresolved','refunds_older_than_24h','kyc_waiting_review','shop_deletions_waiting_or_in_cooling_off','approved_shop_deletions_blocked_by_refunds','disputed_orders','payment_attempts_refund_required'];
        final blockers = (data['blockers'] is List) ? (data['blockers'] as List) : const [];
        final total = blockers.fold<int>(0, (sum, item) => sum + ((item is Map ? item['count'] : 0) as num? ?? 0).toInt());
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Centre de contrôle HAITIKET', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: C.ink)),
          const SizedBox(height: 6),
          const Text('Vue opérationnelle en lecture seule. Vérifiez les files avant chaque mise en production.', style: TextStyle(color: C.muted)),
          const SizedBox(height: 12),
          Card(color: total == 0 ? const Color(0xFFEAF7EF) : const Color(0xFFFFF1EC), child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Icon(total == 0 ? Icons.verified_outlined : Icons.warning_amber_rounded, size: 32, color: total == 0 ? C.green : C.terracotta), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(total == 0 ? 'Aucun bloqueur recensé par cet audit' : '$total éléments signalés', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), const Text('Ce résultat ne remplace pas les tests de staging ni la confirmation des prestataires.')]))])),
          const SizedBox(height: 8),
          for (final key in keys) Card(child: ListTile(leading: Icon(((data[key] as num?) ?? 0) > 0 ? Icons.error_outline : Icons.check_circle_outline, color: ((data[key] as num?) ?? 0) > 0 ? C.terracotta : C.green), title: Text(_label(key)), trailing: Text('${data[key] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)))),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Actualiser les contrôles')),
          FilledButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data))); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rapport JSON copié dans le presse-papiers.'))); }, icon: const Icon(Icons.copy_all_outlined), label: const Text('Copier le rapport JSON')),
          const SizedBox(height: 10),
          Text('Dernière génération : ${data['generated_at'] ?? 'inconnue'}', style: const TextStyle(color: C.muted, fontSize: 12)),
          const Text('Aucune opération financière ou fermeture de boutique n’est exécutée depuis cet écran.', style: TextStyle(color: C.muted, fontSize: 12)),
        ]);
      },
    ),
  );
}
