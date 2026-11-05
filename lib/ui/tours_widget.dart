import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';

/// Côté livreur : tournées planifiées/en cours avec la liste ordonnée des arrêts (chaque arrêt garde ses propres codes PIN/QR).
class MyToursCard extends StatelessWidget {
  const MyToursCard({super.key});

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await Supabase.instance.client.rpc('my_tours');
    return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _load(),
        builder: (_, s) {
          final l = s.data ?? const <Map<String, dynamic>>[];
          if (l.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 12),
            const Text('Mes tournées', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.ink)),
            for (final t in l)
              Card(
                color: C.mint,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${t['center_name'] ?? 'Tournée'} · ${t['status'] == 'active' ? 'en cours' : 'planifiée'}', style: const TextStyle(fontWeight: FontWeight.w900, color: C.ink)),
                    if (t['center_address'] != null) Text('Départ : ${t['center_address']}', style: const TextStyle(color: C.muted)),
                    for (final it in (t['items'] as List)) Text('${it['seq']}. ${it['dropoff']} — ${it['job_status']}'),
                    if (t['notes'] != null) Text('Note : ${t['notes']}', style: const TextStyle(color: C.muted)),
                  ]),
                ),
              ),
          ]);
        },
      );
}
