import 'dark_mode.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'admin_pro.dart' show AdminUserDetail;
import 'screens5.dart';
import 'widgets.dart';

SupabaseClient get _db => Supabase.instance.client;

Future<List<Map<String, dynamic>>> _rows(String fn, [Map<String, dynamic>? p]) async {
  final r = await _db.rpc(fn, params: p);
  return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

String _d(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '—';
  String t(int x) => x.toString().padLeft(2, '0');
  return '${t(d.day)}/${t(d.month)} ${t(d.hour)}:${t(d.minute)}';
}

num _num(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);

// ---------------------------------------------------------------------------
// Carte LIVE : livreurs, missions ouvertes, livraisons en cours, boutiques, centres (actualisée toutes les 10 s)
// ---------------------------------------------------------------------------
const _tileUrl = String.fromEnvironment('MAP_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');

class AdminLiveMapPage extends StatefulWidget {
  const AdminLiveMapPage({super.key});
  @override
  State<AdminLiveMapPage> createState() => _AdminLiveMapPageState();
}

class _AdminLiveMapPageState extends State<AdminLiveMapPage> {
  Map<String, dynamic>? data;
  String? error;
  Timer? timer;
  DateTime? updated;
  bool showShops = true;

  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await _db.rpc('admin_live_map');
      if (!mounted) return;
      setState(() {
        data = Map<String, dynamic>.from(r as Map);
        error = null;
        updated = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => error = Repo.err(e));
    }
  }

  List<Map<String, dynamic>> list(String k) => ((data?[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Marker pin(double lat, double lng, IconData icon, Color color, String label) => Marker(
        point: LatLng(lat, lng),
        width: 42,
        height: 42,
        child: GestureDetector(
          onTap: () => toast(context, label),
          child: Container(
            decoration: BoxDecoration(color: C.card, shape: BoxShape.circle, border: Border.all(color: color, width: 3), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)]),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final couriers = list('couriers'), jobs = list('open_jobs'), deliveries = list('deliveries'), shops = list('shops'), centers = list('centers');
    final markers = <Marker>[
      if (showShops)
        for (final s in shops) pin(_num(s['lat']).toDouble(), _num(s['lng']).toDouble(), s['kind'] == 'platform' ? Icons.verified : Icons.storefront, s['kind'] == 'platform' ? C.green : C.terracotta, '${s['name']}'),
      for (final c in centers) pin(_num(c['lat']).toDouble(), _num(c['lng']).toDouble(), Icons.warehouse_outlined, C.ink, 'Centre : ${c['name']}'),
      for (final j in jobs) if (j['lat'] != null) pin(_num(j['lat']).toDouble(), _num(j['lng']).toDouble(), Icons.hourglass_top, C.yellow, 'Mission ouverte depuis ${j['age_min']} min · ${j['area']}'),
      for (final x in deliveries) pin(_num(x['lat']).toDouble(), _num(x['lng']).toDouble(), Icons.flag, const Color(0xFF3B6FD4), 'Destination · ${x['address']} (${x['status']})'),
      for (final c in couriers)
        pin(_num(c['lat']).toDouble(), _num(c['lng']).toDouble(), Icons.two_wheeler, c['on_job'] == true ? const Color(0xFF3B6FD4) : (c['available'] == true ? const Color(0xFF25D366) : Colors.grey),
            '${c['name']} · ${c['on_job'] == true ? 'en mission' : (c['available'] == true ? 'disponible' : 'hors ligne')} · position il y a ${_num(c['age_s']).toInt()} s'),
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Wrap(spacing: 14, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Carte en direct', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: C.ink)),
          Text('${couriers.length} livreurs · ${jobs.length} missions ouvertes · ${deliveries.length} livraisons en cours', style: TextStyle(color: C.muted)),
          Text(updated == null ? 'chargement…' : 'mis à jour ${_d(updated!.toIso8601String())}', style: TextStyle(color: C.muted, fontSize: 12)),
          FilterChip(label: const Text('Boutiques'), selected: showShops, onSelected: (v) => setState(() => showShops = v)),
          IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
        ]),
      ),
      if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: Wrap(spacing: 12, children: [
          Text('🟢 disponible', style: TextStyle(fontSize: 12)), Text('🔵 en mission / destination', style: TextStyle(fontSize: 12)),
          Text('🟡 mission sans livreur', style: TextStyle(fontSize: 12)), Text('⚪ hors ligne', style: TextStyle(fontSize: 12)),
        ]),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: FlutterMap(
            options: const MapOptions(initialCenter: LatLng(18.5392, -72.3364), initialZoom: 11, minZoom: 3, maxZoom: 18),
            children: [
              TileLayer(tileBuilder: darkTileBuilder, urlTemplate: _tileUrl, userAgentPackageName: 'com.haitiket.haitiket'),
              MarkerLayer(markers: markers),
            ],
          ),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Logistique : centres, tournées multi-commandes, scans
// ---------------------------------------------------------------------------
class AdminLogisticsPage extends StatelessWidget {
  const AdminLogisticsPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(children: [
          TabBar(labelColor: C.ink, indicatorColor: C.terracotta, tabs: [Tab(text: 'Centres'), Tab(text: 'Tournées'), Tab(text: 'Scans')]),
          Expanded(child: TabBarView(children: [_CentersTab(), _ToursTab(), _ScansTab()])),
        ]),
      );
}

class _CentersTab extends StatefulWidget {
  const _CentersTab();
  @override
  State<_CentersTab> createState() => _CentersTabState();
}

class _CentersTabState extends State<_CentersTab> {
  late Future<List<Map<String, dynamic>>> f = _rows('admin_list_centers');
  void reload() => setState(() => f = _rows('admin_list_centers'));

  Future<void> edit([Map<String, dynamic>? c]) async {
    final name = TextEditingController(text: '${c?['name'] ?? ''}');
    final city = TextEditingController(text: '${c?['city'] ?? ''}');
    final address = TextEditingController(text: '${c?['address'] ?? ''}');
    final zone = TextEditingController(text: '${c?['zone'] ?? ''}');
    final lat = TextEditingController(text: c?['lat'] == null ? '' : '${c?['lat']}');
    final lng = TextEditingController(text: c?['lng'] == null ? '' : '${c?['lng']}');
    final cap = TextEditingController(text: '${c?['capacity'] ?? 50}');
    var kind = '${c?['kind'] ?? 'center'}';
    var active = c?['active'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: Text(c == null ? 'Nouveau centre / point' : 'Modifier'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
              DropdownButtonFormField<String>(value: kind, decoration: const InputDecoration(labelText: 'Type'), items: const [
                DropdownMenuItem(value: 'center', child: Text('Centre HAITIKET')),
                DropdownMenuItem(value: 'pickup_point', child: Text('Point de collecte')),
                DropdownMenuItem(value: 'partner', child: Text('Partenaire logistique')),
              ], onChanged: (v) => setD(() => kind = v ?? 'center')),
              TextField(controller: city, decoration: const InputDecoration(labelText: 'Ville')),
              TextField(controller: address, decoration: const InputDecoration(labelText: 'Adresse')),
              TextField(controller: zone, decoration: const InputDecoration(labelText: 'Zone desservie')),
              Row(children: [
                Expanded(child: TextField(controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Latitude'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Longitude'))),
              ]),
              TextField(controller: cap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacité (colis)')),
              SwitchListTile(value: active, onChanged: (v) => setD(() => active = v), title: const Text('Actif')),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer'))],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _db.rpc('admin_upsert_center', params: {
        'p_id': c?['id'], 'p_name': name.text, 'p_kind': kind, 'p_city': city.text, 'p_address': address.text, 'p_zone': zone.text,
        'p_lat': double.tryParse(lat.text.replaceAll(',', '.')), 'p_lng': double.tryParse(lng.text.replaceAll(',', '.')),
        'p_capacity': int.tryParse(cap.text) ?? 50, 'p_active': active,
      });
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: f,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) return EmptyState(title: 'Erreur', text: Repo.err(s.error!));
          final l = s.data ?? [];
          return ListView(padding: const EdgeInsets.all(14), children: [
            FilledButton.icon(onPressed: () => edit(), icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Ajouter un centre / point de collecte')),
            const SizedBox(height: 8),
            if (l.isEmpty) const EmptyState(title: 'Aucun centre', text: 'Ajoutez votre premier centre logistique.'),
            for (final c in l)
              Card(
                color: c['active'] == false ? C.soft : C.card,
                child: ListTile(
                  leading: Icon(c['kind'] == 'partner' ? Icons.handshake_outlined : (c['kind'] == 'pickup_point' ? Icons.place_outlined : Icons.warehouse_outlined), color: C.green),
                  title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${c['city'] ?? ''} ${c['address'] ?? ''}\nZone : ${c['zone'] ?? '—'} · capacité ${c['capacity']} · ${c['lat'] == null ? 'sans position' : '${c['lat']}, ${c['lng']}'}'),
                  isThreeLine: true,
                  trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => edit(c)),
                ),
              ),
          ]);
        },
      );
}

class _ToursTab extends StatefulWidget {
  const _ToursTab();
  @override
  State<_ToursTab> createState() => _ToursTabState();
}

class _ToursTabState extends State<_ToursTab> {
  String status = 'all';
  late Future<List<Map<String, dynamic>>> f = load();
  Future<List<Map<String, dynamic>>> load() async => ((await _db.rpc('admin_list_tours', params: {'p_status': status})) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  void reload() => setState(() => f = load());

  Future<void> run(Future<dynamic> Function() a, String ok) async {
    try {
      await a();
      if (mounted) toast(context, ok);
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> create() async {
    List<Map<String, dynamic>> centers = [], couriers = [];
    try {
      centers = (await _rows('admin_list_centers')).where((c) => c['active'] == true).toList();
      couriers = await _rows('admin_list_couriers');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
      return;
    }
    if (couriers.isEmpty) {
      if (mounted) toast(context, 'Aucun livreur approuvé.');
      return;
    }
    String? center;
    String? courier = couriers.first['user_id'] as String;
    final cap = TextEditingController(text: '8');
    final notes = TextEditingController();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: const Text('Nouvelle tournée'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String?>(value: center, decoration: const InputDecoration(labelText: 'Centre de départ'), items: [const DropdownMenuItem<String?>(value: null, child: Text('— Sans centre')), for (final c in centers) DropdownMenuItem<String?>(value: c['id'] as String, child: Text('${c['name']}'))], onChanged: (v) => setD(() => center = v)),
              DropdownButtonFormField<String?>(value: courier, decoration: const InputDecoration(labelText: 'Livreur'), items: [for (final c in couriers) DropdownMenuItem<String?>(value: c['user_id'] as String, child: Text('${c['full_name']}${c['available'] == true ? ' ●' : ''}'))], onChanged: (v) => setD(() => courier = v)),
              TextField(controller: cap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacité (commandes, max 50)')),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Créer'))],
        ),
      ),
    );
    if (ok != true) return;
    await run(() => _db.rpc('admin_create_tour', params: {'p_center': center, 'p_courier': courier, 'p_capacity': int.tryParse(cap.text) ?? 8, 'p_notes': notes.text}), 'Tournée créée.');
  }

  Future<void> addStop(String tour) async {
    final id = await askText(context, 'N° de la commande à ajouter', hint: 'Collez l’identifiant complet (copiable dans Commandes)');
    if (id == null || id.trim().length < 30) return;
    await run(() => _db.rpc('admin_add_tour_stop', params: {'p_tour': tour, 'p_order': id.trim()}), 'Commande ajoutée à la tournée.');
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: create, icon: const Icon(Icons.add_road), label: const Text('Nouvelle tournée'))),
          const SizedBox(width: 10),
          DropdownButton<String>(value: status, items: const [
            DropdownMenuItem(value: 'all', child: Text('Toutes')), DropdownMenuItem(value: 'planned', child: Text('Planifiées')),
            DropdownMenuItem(value: 'active', child: Text('En cours')), DropdownMenuItem(value: 'completed', child: Text('Terminées')), DropdownMenuItem(value: 'cancelled', child: Text('Annulées')),
          ], onChanged: (v) { status = v ?? 'all'; reload(); }),
        ]),
        Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Une commande ne peut rejoindre une tournée que si sa mission est déjà attribuée au même livreur et non collectée. Chaque commande garde ses propres codes PIN/QR et son historique.', style: TextStyle(color: C.muted, fontSize: 12))),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return EmptyState(title: 'Erreur', text: Repo.err(s.error!));
            final l = s.data ?? [];
            if (l.isEmpty) return const EmptyState(title: 'Aucune tournée', text: 'Créez une tournée pour regrouper plusieurs livraisons.');
            return Column(children: [
              for (final t in l)
                Card(
                  color: C.card,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${t['courier_name'] ?? 'Livreur'} · ${t['center_name'] ?? 'sans centre'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      Text('${t['status']} · ${t['delivered']}/${t['stops']} livrées · capacité ${t['capacity']} · ${_d(t['created_at'])}', style: TextStyle(color: C.muted)),
                      for (final it in (t['items'] as List)) Text('  ${it['seq']}. ${it['dropoff']} — ${it['job_status']}'),
                      Wrap(spacing: 6, children: [
                        if (t['status'] == 'planned' || t['status'] == 'active') TextButton(onPressed: () => addStop('${t['id']}'), child: const Text('+ Commande')),
                        if (t['status'] == 'planned') TextButton(onPressed: () => run(() => _db.rpc('admin_set_tour_status', params: {'p_tour': t['id'], 'p_status': 'active'}), 'Tournée démarrée.'), child: const Text('Démarrer')),
                        if (t['status'] == 'active') TextButton(onPressed: () => run(() => _db.rpc('admin_set_tour_status', params: {'p_tour': t['id'], 'p_status': 'completed'}), 'Tournée terminée.'), child: const Text('Terminer')),
                        if (t['status'] == 'planned' || t['status'] == 'active') TextButton(onPressed: () => run(() => _db.rpc('admin_set_tour_status', params: {'p_tour': t['id'], 'p_status': 'cancelled'}), 'Tournée annulée.'), child: const Text('Annuler', style: TextStyle(color: Colors.redAccent))),
                      ]),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ]);
}

class _ScansTab extends StatefulWidget {
  const _ScansTab();
  @override
  State<_ScansTab> createState() => _ScansTabState();
}

class _ScansTabState extends State<_ScansTab> {
  late Future<List<Map<String, dynamic>>> f = _rows('admin_list_center_scans');
  late Future<List<Map<String, dynamic>>> centers = _rows('admin_list_centers');
  String? center;
  String event = 'received';
  final order = TextEditingController(), note = TextEditingController();

  Future<void> save() async {
    try {
      await _db.rpc('admin_center_scan', params: {'p_center': center, 'p_order': order.text.trim().isEmpty ? null : order.text.trim(), 'p_event': event, 'p_note': note.text});
      order.clear();
      note.clear();
      if (mounted) toast(context, 'Scan enregistré.');
      setState(() => f = _rows('admin_list_center_scans'));
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
        const Text('Enregistrer un passage au centre', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: centers,
          builder: (_, s) => DropdownButtonFormField<String>(
            value: center,
            decoration: const InputDecoration(labelText: 'Centre'),
            items: [for (final c in (s.data ?? [])) DropdownMenuItem(value: c['id'] as String, child: Text('${c['name']}'))],
            onChanged: (v) => setState(() => center = v),
          ),
        ),
        DropdownButtonFormField<String>(value: event, decoration: const InputDecoration(labelText: 'Événement'), items: const [
          DropdownMenuItem(value: 'received', child: Text('Colis reçu')), DropdownMenuItem(value: 'dispatched', child: Text('Colis expédié')),
          DropdownMenuItem(value: 'returned', child: Text('Colis retourné')), DropdownMenuItem(value: 'incident', child: Text('Incident')),
        ], onChanged: (v) => setState(() => event = v ?? 'received')),
        TextField(controller: order, decoration: const InputDecoration(labelText: 'N° de commande (optionnel)')),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: center == null ? null : save, icon: const Icon(Icons.qr_code_scanner), label: const Text('Enregistrer')),
        const Divider(height: 28),
        const Text('Derniers scans', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const LinearProgressIndicator();
            final l = s.data ?? [];
            if (l.isEmpty) return Text('Aucun scan.', style: TextStyle(color: C.muted));
            return Column(children: [for (final r in l) ListTile(dense: true, title: Text('${r['center_name']} · ${r['event']}'), subtitle: Text('${_d(r['created_at'])} ${r['order_id'] ?? ''} ${r['note'] ?? ''}'))]);
          },
        ),
      ]);
}

// ---------------------------------------------------------------------------
// Antifraude : alertes automatiques + examen manuel
// ---------------------------------------------------------------------------
class AdminFraudPage extends StatefulWidget {
  const AdminFraudPage({super.key});
  @override
  State<AdminFraudPage> createState() => _AdminFraudPageState();
}

class _AdminFraudPageState extends State<AdminFraudPage> {
  String status = 'open';
  late Future<List<Map<String, dynamic>>> f = _rows('admin_list_fraud_alerts', {'p_status': status});
  void reload() => setState(() => f = _rows('admin_list_fraud_alerts', {'p_status': status}));

  static const _labels = {
    'double_payment': 'Double paiement', 'coupon_abuse': 'Abus de coupons', 'referral_abuse': 'Abus de parrainage',
    'refund_abuse': 'Abus de remboursement', 'pin_failures': 'Codes de livraison erronés',
  };

  Future<void> scan() async {
    try {
      final n = await _db.rpc('admin_run_fraud_scan');
      if (mounted) toast(context, '$n nouvelle(s) alerte(s).');
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> review(Map<String, dynamic> a, String st) async {
    final note = await askText(context, st == 'reviewed' ? 'Note d’examen' : 'Pourquoi rejeter ?', hint: 'Facultatif');
    if (note == null) return;
    try {
      await _db.rpc('admin_review_fraud_alert', params: {'p_alert': a['id'], 'p_status': st, 'p_note': note});
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: [
        Row(children: [
          Expanded(child: Text('Antifraude', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.ink))),
          FilledButton.icon(onPressed: scan, icon: const Icon(Icons.radar), label: const Text('Lancer l’analyse')),
        ]),
        Text('Détection automatique (toutes les 15 min si pg_cron est actif). Aucune action n’est prise sans votre décision : examinez puis bloquez le compte depuis sa fiche client si nécessaire.', style: TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [for (final s in const [('open', 'À traiter'), ('reviewed', 'Examinées'), ('dismissed', 'Rejetées'), ('all', 'Toutes')]) ChoiceChip(label: Text(s.$2), selected: status == s.$1, onSelected: (_) { status = s.$1; reload(); })]),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
            if (s.hasError) return EmptyState(title: 'Erreur', text: Repo.err(s.error!));
            final l = s.data ?? [];
            if (l.isEmpty) return const EmptyState(title: 'Aucune alerte', text: 'Rien à signaler.');
            return Column(children: [
              for (final a in l)
                Card(
                  color: a['severity'] == 'high' ? C.tint : C.card,
                  child: ListTile(
                    leading: Icon(a['severity'] == 'high' ? Icons.warning_amber_rounded : Icons.flag_outlined, color: a['severity'] == 'high' ? Colors.redAccent : C.yellow),
                    title: Text('${_labels[a['kind']] ?? a['kind']} · ${a['user_name'] ?? 'utilisateur'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${a['detail']}\n${_d(a['created_at'])} · ${a['status']}${a['note'] != null && '${a['note']}'.isNotEmpty ? ' · ${a['note']}' : ''}'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'user' && a['user_id'] != null) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserDetail(userId: '${a['user_id']}')));
                        } else if (v == 'copy') {
                          Clipboard.setData(ClipboardData(text: '${a['order_id'] ?? a['id']}'));
                        } else if (v == 'reviewed' || v == 'dismissed') {
                          review(a, v);
                        }
                      },
                      itemBuilder: (_) => [
                        if (a['user_id'] != null) const PopupMenuItem(value: 'user', child: Text('Ouvrir la fiche client')),
                        const PopupMenuItem(value: 'copy', child: Text('Copier l’identifiant')),
                        if (a['status'] == 'open') const PopupMenuItem(value: 'reviewed', child: Text('Marquer examinée')),
                        if (a['status'] == 'open') const PopupMenuItem(value: 'dismissed', child: Text('Rejeter (faux positif)')),
                      ],
                    ),
                  ),
                ),
            ]);
          },
        ),
      ]);
}

// ---------------------------------------------------------------------------
// Boutique officielle : propriétaire visible et transférable entre administrateurs
// ---------------------------------------------------------------------------
class OfficialShopOwnerCard extends StatefulWidget {
  const OfficialShopOwnerCard({super.key});
  @override
  State<OfficialShopOwnerCard> createState() => _OfficialShopOwnerCardState();
}

class _OfficialShopOwnerCardState extends State<OfficialShopOwnerCard> {
  late Future<Map<String, dynamic>?> f = load();

  Future<Map<String, dynamic>?> load() async {
    final r = await _db.rpc('admin_official_shop_owner');
    return r == null ? null : Map<String, dynamic>.from(r as Map);
  }

  Future<void> transfer(String userId) async {
    try {
      await _db.rpc('admin_set_official_shop_owner', params: {'p_user': userId});
      if (mounted) toast(context, 'Propriété transférée. La boutique apparaît maintenant dans l’espace vendeur du nouveau propriétaire.');
      setState(() => f = load());
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  Future<void> chooseAdmin() async {
    try {
      final l = await _rows('admin_list_admins');
      if (!mounted) return;
      final pick = await showDialog<String>(
        context: context,
        builder: (d) => SimpleDialog(
          title: const Text('Transférer à…'),
          children: [for (final a in l) SimpleDialogOption(onPressed: () => Navigator.pop(d, '${a['user_id']}'), child: Text('${a['name'] ?? 'Admin'} · ${a['email']}'))],
        ),
      );
      if (pick != null) await transfer(pick);
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
        future: f,
        builder: (_, s) {
          final o = s.data;
          if (o == null) return const SizedBox.shrink();
          final me = o['is_me'] == true;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Propriétaire de la boutique officielle', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.ink)),
              const SizedBox(height: 4),
              Text(me ? 'C’est vous : la boutique apparaît dans votre espace vendeur et vous confirmez ses remises (codes PIN/QR).' : '${o['owner_name'] ?? 'Administrateur'} (${o['owner_email']}) — la boutique officielle apparaît dans SON espace vendeur, pas dans le vôtre. Seul le propriétaire confirme les remises ; vous pouvez aussi forcer une remise depuis Admin → Commandes.', style: TextStyle(color: C.muted)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                if (!me) FilledButton.icon(onPressed: () async { final id = _db.auth.currentUser?.id; if (id != null) await transfer(id); }, icon: const Icon(Icons.verified_user_outlined), label: const Text('Devenir le propriétaire')),
                OutlinedButton.icon(onPressed: chooseAdmin, icon: const Icon(Icons.swap_horiz), label: const Text('Transférer à un autre admin')),
              ]),
            ]),
          );
        },
      );
}
