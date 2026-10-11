import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../data/repo.dart';
import '../i18n.dart';
import '../theme.dart';
import 'fx.dart';
import 'screens5.dart';
import 'widgets.dart';

// Fond de carte : OpenStreetMap par défaut. Pour un usage commercial intensif, remplacez-le par un fournisseur
// (MapTiler, Stadia…) en ajoutant --dart-define=MAP_TILE_URL=... dans le workflow.
const _tileUrl = String.fromEnvironment('MAP_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');

/// Mémoire des boutiques géolocalisées : la carte s'ouvre instantanément avec les données déjà chargées.
class ShopGeoCache {
  static List<Map<String, dynamic>> data = [];
  static DateTime? at;
  static bool get fresh => at != null && DateTime.now().difference(at!) < const Duration(seconds: 60);
  static Future<List<Map<String, dynamic>>> load({bool force = false}) async {
    if (!force && fresh) return data;
    data = await Repo.shopsGeo();
    at = DateTime.now();
    return data;
  }
}

class _Pin extends StatelessWidget {
  final Map<String, dynamic> shop;
  final bool selected;
  final Animation<double> pulse;
  final VoidCallback onTap;
  const _Pin({super.key, required this.shop, required this.selected, required this.pulse, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final pro = shop['kind'] == 'pro';
    final accent = hexColor(shop['color_accent'] as String?) ?? (pro ? C.terracotta : C.yellow);
    final logo = shop['logo_url'] as String?;
    final size = selected ? 54.0 : 44.0;
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 650),
        curve: Curves.elasticOut,
        builder: (_, t, child) => Transform.scale(scale: t, child: child),
        child: Stack(alignment: Alignment.center, children: [
          if (selected)
            AnimatedBuilder(
              animation: pulse,
              builder: (_, __) => Container(width: 44 + 40 * pulse.value, height: 44 + 40 * pulse.value, decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: .38 * (1 - pulse.value)))),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            width: size,
            height: size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: accent, width: selected ? 4 : 3), boxShadow: [BoxShadow(color: accent.withValues(alpha: .55), blurRadius: selected ? 18 : 7)]),
            child: logo != null ? Image.network(logo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.storefront, color: accent)) : Icon(pro ? Icons.storefront : Icons.person_pin_circle, color: accent, size: selected ? 30 : 24),
          ),
        ]),
      ),
    );
  }
}

class _Cluster extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _Cluster({required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final size = 42.0 + math.min(count, 20) * 1.2;
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: .3, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.elasticOut,
        builder: (_, t, child) => Transform.scale(scale: t, child: child),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [C.ink, C.green], begin: Alignment.topLeft, end: Alignment.bottomRight), border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 10)]),
          child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
        ),
      ),
    );
  }
}

class MapScreen extends StatefulWidget {
  final String? kind; // 'pro' | 'personal' | null
  const MapScreen({super.key, this.kind});
  @override
  State<MapScreen> createState() => _MapState();
}

class _MapState extends State<MapScreen> with TickerProviderStateMixin {
  final mc = MapController();
  final pages = PageController(viewportFraction: .88);
  final searchC = TextEditingController();
  late final AnimationController pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat();
  AnimationController? fly;
  List<Map<String, dynamic>> shops = ShopGeoCache.data;
  bool loading = false, ready = false, routing = false, routeDotted = false;
  late String kind = widget.kind ?? 'all';
  String q = '';
  Position? me;
  String? selectedId;
  double zoom = 10.5;
  List<LatLng> route = [];
  Map<String, dynamic>? routeInfo;

  @override
  void initState() {
    super.initState();
    refresh(force: !ShopGeoCache.fresh);
  }

  @override
  void dispose() {
    pulse.dispose();
    fly?.dispose();
    pages.dispose();
    searchC.dispose();
    super.dispose();
  }

  Future<void> refresh({bool force = false}) async {
    setState(() => loading = true);
    try {
      final d = await ShopGeoCache.load(force: force);
      if (mounted) setState(() => shops = d);
      WidgetsBinding.instance.addPostFrameCallback((_) => fitAll());
    } catch (_) {
      if (mounted) toast(context, 'Actualisation impossible. Vérifiez votre connexion.');
    }
    if (mounted) setState(() => loading = false);
  }

  LatLng pos(Map<String, dynamic> s) => LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble());
  double dist(Map<String, dynamic> s) {
    final p = pos(s);
    return distKm(me!.latitude, me!.longitude, p.latitude, p.longitude);
  }

  List<Map<String, dynamic>> get visible {
    final l = shops.where((s) => kind == 'all' || s['kind'] == kind).where((s) => q.isEmpty || '${s['name']} ${s['city'] ?? ''}'.toLowerCase().contains(q.toLowerCase())).toList();
    if (me != null) l.sort((a, b) => dist(a).compareTo(dist(b)));
    return l;
  }

  void fitAll() {
    if (!ready || !mounted) return;
    final l = visible;
    if (l.isEmpty || selectedId != null) return;
    try {
      if (l.length == 1) {
        flyTo(pos(l.first), 14);
      } else {
        mc.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints([for (final s in l) pos(s)]), padding: const EdgeInsets.fromLTRB(50, 170, 50, 260), maxZoom: 15));
      }
    } catch (_) {}
  }

  /// Vol animé : léger recul puis zoom, pour un effet « caméra ».
  void flyTo(LatLng dest, double destZoom) {
    if (!ready) return;
    try {
      fly?.dispose();
      final c = fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 950));
      final from = mc.camera.center;
      final z0 = mc.camera.zoom;
      final curve = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic);
      c.addListener(() {
        final t = curve.value;
        final z = z0 + (destZoom - z0) * t - math.sin(math.pi * t) * 1.1;
        mc.move(LatLng(from.latitude + (dest.latitude - from.latitude) * t, from.longitude + (dest.longitude - from.longitude) * t), z.clamp(3.0, 18.0));
      });
      c.forward();
    } catch (_) {}
  }

  void select(Map<String, dynamic> s, {bool scroll = true}) {
    HapticFeedback.selectionClick();
    setState(() {
      selectedId = s['id'] as String;
      route = [];
      routeInfo = null;
    });
    final i = visible.indexWhere((x) => x['id'] == s['id']);
    if (scroll && i >= 0 && pages.hasClients) pages.animateToPage(i, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    flyTo(pos(s), math.max(zoom, 14.5));
  }

  Future<void> locate() async {
    final p = await myPosition(context);
    if (p == null || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => me = p);
    flyTo(LatLng(p.latitude, p.longitude), 15);
  }

  Future<void> routeTo(Map<String, dynamic> s) async {
    if (me == null) await locate();
    if (me == null || !mounted) return;
    final dest = pos(s);
    final start = LatLng(me!.latitude, me!.longitude);
    setState(() => routing = true);
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${dest.longitude},${dest.latitude}?overview=full&geometries=geojson';
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 9));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final rt = (d['routes'] as List).first as Map<String, dynamic>;
      final pts = [for (final c in (rt['geometry']['coordinates'] as List)) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())];
      if (!mounted) return;
      setState(() {
        route = pts;
        routeDotted = false;
        routeInfo = {'km': (rt['distance'] as num) / 1000, 'min': ((rt['duration'] as num) / 60).round(), 'road': true};
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        route = [start, dest];
        routeDotted = true;
        routeInfo = {'km': distKm(start.latitude, start.longitude, dest.latitude, dest.longitude), 'min': null, 'road': false};
      });
      toast(context, "Itinéraire routier indisponible : distance à vol d'oiseau affichée.");
    }
    if (mounted) {
      setState(() => routing = false);
      try {
        mc.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(route), padding: const EdgeInsets.fromLTRB(50, 170, 50, 280)));
      } catch (_) {}
    }
  }

  List<Marker> markers() {
    final list = visible;
    final deg = 70 * 360 / (256 * math.pow(2, zoom.round()).toDouble());
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final s in list) {
      if (s['id'] == selectedId || zoom >= 15) {
        groups['id_${s['id']}'] = [s];
        continue;
      }
      final p = pos(s);
      (groups['${(p.latitude / deg).floor()}_${(p.longitude / deg).floor()}'] ??= []).add(s);
    }
    final out = <Marker>[];
    for (final g in groups.values) {
      if (g.length == 1) {
        final s = g.first;
        out.add(Marker(point: pos(s), width: 90, height: 90, child: _Pin(key: ValueKey(s['id']), shop: s, selected: s['id'] == selectedId, pulse: pulse, onTap: () => select(s))));
      } else {
        final lat = g.map((s) => (s['lat'] as num).toDouble()).reduce((a, b) => a + b) / g.length;
        final lng = g.map((s) => (s['lng'] as num).toDouble()).reduce((a, b) => a + b) / g.length;
        out.add(Marker(point: LatLng(lat, lng), width: 70, height: 70, child: _Cluster(count: g.length, onTap: () => flyTo(LatLng(lat, lng), math.min(zoom + 2.4, 17)))));
      }
    }
    if (me != null) {
      out.add(Marker(
        point: LatLng(me!.latitude, me!.longitude),
        width: 70,
        height: 70,
        child: AnimatedBuilder(
          animation: pulse,
          builder: (_, __) => Stack(alignment: Alignment.center, children: [
            Container(width: 20 + 44 * pulse.value, height: 20 + 44 * pulse.value, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue.withValues(alpha: .3 * (1 - pulse.value)))),
            Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6)])),
          ]),
        ),
      ));
    }
    return out;
  }

  Widget fab(IconData i, VoidCallback onTap, {bool spin = false}) => Pressable(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          margin: const EdgeInsets.only(top: 10),
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))]),
          child: spin ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 3)) : Icon(i, color: C.ink),
        ),
      );

  Widget pill(String label, String value) {
    final sel = kind == value;
    return Pressable(
      onTap: () => setState(() {
        kind = value;
        selectedId = null;
        route = [];
        routeInfo = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => fitAll());
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(color: sel ? C.ink : Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)]),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: sel ? Colors.white : C.ink)),
      ),
    );
  }

  Widget card(Map<String, dynamic> s) {
    final pro = s['kind'] == 'pro';
    final accent = hexColor(s['color_accent'] as String?) ?? (pro ? C.terracotta : C.yellow);
    final primary = hexColor(s['color_primary'] as String?) ?? C.ink;
    final logo = s['logo_url'] as String?;
    final isSel = s['id'] == selectedId;
    final slogan = (s['slogan'] as String?) ?? (s['city'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), border: Border.all(color: isSel ? accent : Colors.transparent, width: 2.5), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 24, backgroundColor: accent, backgroundImage: logo == null ? null : NetworkImage(logo), child: logo == null ? Icon(pro ? Icons.storefront : Icons.person, color: Colors.white) : null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: primary)),
                Text(slogan, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)),
              ]),
            ),
            if (me != null) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(12)), child: Text(fmtKm(dist(s)), style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
          ]),
          const SizedBox(height: 6),
          if (isSel && routeInfo != null)
            Text(routeInfo!['road'] == true ? '${(routeInfo!['km'] as num).toStringAsFixed(1)} km · environ ${routeInfo!['min']} min en voiture (estimation)' : "${fmtKm((routeInfo!['km'] as num).toDouble())} à vol d'oiseau", style: const TextStyle(color: C.green, fontWeight: FontWeight.w800))
          else
            Text(pro ? 'Boutique professionnelle' : 'Vendeur du Bazar', style: const TextStyle(color: C.muted)),
          const Spacer(),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: routing ? null : () => routeTo(s), icon: const Icon(Icons.directions, size: 20), label: Text(routing && isSel ? '…' : 'Itinéraire'))),
            const SizedBox(width: 10),
            Expanded(child: PrimaryButton(label: 'Boutique', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(s['id'] as String))))),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = visible;
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: mc,
          options: MapOptions(
            initialCenter: const LatLng(18.5392, -72.335),
            initialZoom: 10.5,
            minZoom: 4,
            maxZoom: 18,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onMapReady: () {
              ready = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => fitAll());
            },
            onPositionChanged: (cam, gesture) {
              final z = cam.zoom;
              final changed = z.round() != zoom.round();
              zoom = z;
              if (changed) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
              }
            },
          ),
          children: [
            TileLayer(urlTemplate: _tileUrl, userAgentPackageName: 'com.haitiket.haitiket', panBuffer: 2, keepBuffer: 4),
            if (route.isNotEmpty) PolylineLayer(polylines: [Polyline(points: route, strokeWidth: 6, color: C.terracotta, borderStrokeWidth: 2, borderColor: Colors.white, isDotted: routeDotted)]),
            MarkerLayer(markers: markers()),
            const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
          ],
        ),
        // Recherche + filtres
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Pressable(onTap: () => Navigator.of(context).pop(), child: Container(width: 48, height: 48, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 10)]), child: const Icon(Icons.arrow_back, color: C.ink))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10)]),
                      child: Row(children: [
                        const Icon(Icons.search, color: C.muted),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: searchC, onChanged: (v) => setState(() => q = v.trim()), decoration: const InputDecoration(hintText: 'Rechercher une boutique ou une ville', border: InputBorder.none, enabledBorder: InputBorder.none, filled: false, isDense: true))),
                        if (q.isNotEmpty) GestureDetector(onTap: () => setState(() { q = ''; searchC.clear(); }), child: const Icon(Icons.close, color: C.muted)),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [pill('Tout', 'all'), pill('Boutiques pro', 'pro'), pill('Bazar', 'personal'), Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(22)), child: Text('${list.length} lieu(x)', style: const TextStyle(fontWeight: FontWeight.w900, color: C.ink)))])),
                if (loading) const Padding(padding: EdgeInsets.only(top: 8), child: ClipRRect(borderRadius: BorderRadius.all(Radius.circular(8)), child: LinearProgressIndicator(minHeight: 4, color: C.terracotta, backgroundColor: Colors.white))),
              ]),
            ),
          ),
        ),
        // Boutons flottants
        Positioned(
          right: 12,
          bottom: 232,
          child: Column(children: [
            fab(Icons.my_location, locate),
            fab(Icons.refresh, () => refresh(force: true), spin: loading),
            fab(Icons.zoom_out_map, () {
              setState(() {
                selectedId = null;
                route = [];
                routeInfo = null;
              });
              fitAll();
            }),
          ]),
        ),
        // Carrousel des boutiques
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 200,
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                        child: Text(shops.isEmpty ? "Aucune boutique n'a encore partagé sa position." : 'Aucun résultat pour ces filtres.', style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                      ),
                    )
                  : PageView.builder(
                      controller: pages,
                      itemCount: list.length,
                      onPageChanged: (i) {
                        final l = visible;
                        if (i < l.length && l[i]['id'] != selectedId) select(l[i], scroll: false);
                      },
                      itemBuilder: (_, i) => card(list[i]),
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}
