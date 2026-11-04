import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'widgets.dart';

/// Normalise un numéro haïtien : « 37 00 0000 » → 50937000000 (sans +, pour wa.me).
String _digits(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length == 8) d = '509$d';
  return d;
}

Future<void> _open(BuildContext c, Uri uri) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && c.mounted) toast(c, "Impossible d'ouvrir cette application.");
}

/// Carte « Contacts de la livraison » : appeler ou écrire sur WhatsApp les autres participants
/// d'une commande (client ↔ vendeur ↔ livreur). Les numéros viennent de la RPC sécurisée order_contacts.
class ContactsCard extends StatefulWidget {
  final String? orderId;
  final String? jobId;
  const ContactsCard({super.key, this.orderId, this.jobId});
  @override
  State<ContactsCard> createState() => _ContactsCardState();
}

class _ContactsCardState extends State<ContactsCard> {
  late Future<List<Map<String, dynamic>>> f = widget.jobId != null ? Repo.jobContacts(widget.jobId!) : Repo.orderContacts(widget.orderId!);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: f,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 2));
          final l = s.data ?? const <Map<String, dynamic>>[];
          if (s.hasError || l.isEmpty) return const SizedBox.shrink();
          return Card(
            color: C.mint,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Contacts de la livraison', style: TextStyle(fontWeight: FontWeight.w900, color: C.ink, fontSize: 16)),
                const SizedBox(height: 6),
                for (final p in l) _row(context, p),
              ]),
            ),
          );
        },
      );

  Widget _row(BuildContext context, Map<String, dynamic> p) {
    final phone = '${p['phone'] ?? ''}'.trim();
    final wa = _digits('${p['whatsapp'] ?? ''}');
    final role = '${p['role'] ?? ''}';
    final label = role.isEmpty ? '' : '${role[0].toUpperCase()}${role.substring(1)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$label · ${p['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
            Text(phone.isEmpty ? 'Numéro non renseigné' : phone, style: const TextStyle(color: C.muted)),
          ]),
        ),
        IconButton(
          tooltip: 'Appeler',
          icon: const Icon(Icons.call, color: C.green),
          onPressed: phone.isEmpty ? null : () => _open(context, Uri(scheme: 'tel', path: phone)),
        ),
        IconButton(
          tooltip: 'WhatsApp',
          icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
          onPressed: wa.isEmpty ? null : () => _open(context, Uri.parse('https://wa.me/$wa')),
        ),
      ]),
    );
  }
}
