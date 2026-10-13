import 'package:flutter/material.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'fx.dart';
import 'screens5.dart';
import 'widgets.dart';

const departements = ['Ouest', 'Nord', 'Nord-Est', 'Nord-Ouest', 'Artibonite', 'Centre', 'Sud', 'Sud-Est', "Grand'Anse", 'Nippes'];

/// Texte d'adresse transmis à la commande (aux seuls acteurs qui en ont besoin).
String formatAddress(Map<String, dynamic> a) {
  String v(String k) => (a[k] ?? '').toString().trim();
  final parts = <String>[
    [v('recipient'), v('phone')].where((e) => e.isNotEmpty).join(' · '),
    [v('street'), v('quarter'), v('commune'), v('department')].where((e) => e.isNotEmpty).join(', '),
    if (v('landmarks').isNotEmpty) 'Repères : ${v('landmarks')}',
    if (v('instructions').isNotEmpty) 'Instructions : ${v('instructions')}',
    if (a['lat'] != null && a['lng'] != null) 'GPS : ${(a['lat'] as num).toStringAsFixed(5)}, ${(a['lng'] as num).toStringAsFixed(5)}',
  ];
  return parts.where((e) => e.isNotEmpty).join(' — ');
}

Future<void> reportDialog(BuildContext context, String kind, String target) async {
  final reason = await askText(context, 'Pourquoi signaler ?', hint: 'Décrivez le problème (5 caractères minimum)');
  if (reason == null || reason.length < 5) return;
  try {
    await Repo.submitReport(kind, target, reason);
    if (context.mounted) toast(context, 'Signalement envoyé. Merci : notre équipe va l\'examiner.');
  } catch (e) {
    if (context.mounted) toast(context, Repo.err(e));
  }
}

Future<void> disputeDialog(BuildContext context, String orderId) async {
  final reason = await askText(context, 'Décrivez le problème', hint: 'Article non reçu, endommagé, non conforme…');
  if (reason == null || reason.length < 5) return;
  try {
    await Repo.openDispute(orderId, reason);
    if (context.mounted) toast(context, 'Litige ouvert. Un administrateur va examiner votre dossier.');
  } catch (e) {
    if (context.mounted) toast(context, Repo.err(e));
  }
}

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});
  @override
  State<AddressesScreen> createState() => _AddressesState();
}

class _AddressesState extends State<AddressesScreen> {
  late Future<List<Map<String, dynamic>>> f = Repo.myAddresses();
  void reload() => setState(() => f = Repo.myAddresses());

  Future<void> run(Future<void> Function() a) async {
    try {
      await a();
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mes adresses', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: C.ink,
          foregroundColor: Colors.white,
          onPressed: () async {
            final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AddressFormScreen()));
            if (ok == true) reload();
          },
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Ajouter'),
        ),
        body: currentUser() == null
            ? const Padding(padding: EdgeInsets.all(18), child: EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour enregistrer vos adresses.'))
            : FutureBuilder<List<Map<String, dynamic>>>(
                future: f,
                builder: (_, s) {
                  if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  final l = s.data ?? [];
                  if (l.isEmpty) return const Padding(padding: EdgeInsets.all(18), child: EmptyState(title: 'Aucune adresse', text: 'Ajoutez une adresse : vos livraisons seront plus rapides. Les repères locaux sont acceptés, le GPS est facultatif.'));
                  return ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 100), children: [
                    for (final a in l)
                      Card(
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text('${a['label']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: C.ink))),
                              if (a['is_default'] == true) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(12)), child: const Text('Par défaut', style: TextStyle(fontWeight: FontWeight.w800, color: C.green))),
                            ]),
                            const SizedBox(height: 6),
                            Text(formatAddress(a), style: const TextStyle(color: C.muted, height: 1.4)),
                            Wrap(children: [
                              if (a['is_default'] != true) TextButton(onPressed: () => run(() => Repo.setDefaultAddress(a['id'] as String)), child: const Text('Définir par défaut')),
                              TextButton(onPressed: () => run(() => Repo.deleteAddress(a['id'] as String)), child: const Text('Supprimer')),
                            ]),
                          ]),
                        ),
                      ),
                  ]);
                },
              ),
      );
}

class AddressFormScreen extends StatefulWidget {
  const AddressFormScreen({super.key});
  @override
  State<AddressFormScreen> createState() => _AddressFormState();
}

class _AddressFormState extends State<AddressFormScreen> {
  final label = TextEditingController(text: 'Domicile'), recipient = TextEditingController(), phone = TextEditingController(), commune = TextEditingController();
  final quarter = TextEditingController(), street = TextEditingController(), landmarks = TextEditingController(), instructions = TextEditingController();
  String? dept;
  double? lat, lng;
  bool busy = false;

  Future<void> useGps() async {
    final p = await myPosition(context);
    if (p == null || !mounted) return;
    setState(() {
      lat = p.latitude;
      lng = p.longitude;
    });
    toast(context, 'Position enregistrée avec cette adresse.');
  }

  Future<void> save() async {
    if (recipient.text.trim().length < 2 || commune.text.trim().length < 2) return toast(context, 'Nom du destinataire et commune requis.');
    setState(() => busy = true);
    try {
      String? n(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      final first = (await Repo.myAddresses()).isEmpty;
      await Repo.saveAddress({
        'label': label.text.trim().isEmpty ? 'Adresse' : label.text.trim(),
        'recipient': recipient.text.trim(),
        'phone': n(phone),
        'department': dept,
        'commune': commune.text.trim(),
        'quarter': n(quarter),
        'street': n(street),
        'landmarks': n(landmarks),
        'instructions': n(instructions),
        'lat': lat,
        'lng': lng,
        'is_default': first,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Nouvelle adresse', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          Field(label, 'Nom de l\'adresse (Domicile, Bureau…)'),
          Field(recipient, 'Nom du destinataire'),
          Field(phone, 'Téléphone de contact', type: TextInputType.phone),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Département'),
            items: [for (final d in departements) DropdownMenuItem(value: d, child: Text(d))],
            onChanged: (v) => dept = v,
          ),
          const SizedBox(height: 12),
          Field(commune, 'Commune (ex. Delmas, Pétion-Ville)'),
          Field(quarter, 'Quartier'),
          Field(street, 'Rue ou indication locale'),
          Field(landmarks, 'Repères utiles (ex. en face de l\'église, près du marché)'),
          Field(instructions, 'Instructions de livraison'),
          OutlinedButton.icon(onPressed: useGps, icon: const Icon(Icons.my_location), label: Text(lat == null ? 'Ajouter ma position GPS (facultatif)' : 'Position GPS ajoutée ✓')),
          const SizedBox(height: 18),
          PrimaryButton(label: busy ? 'Enregistrement…' : 'Enregistrer', icon: Icons.check, onPressed: busy ? null : save),
        ]),
      );
}
