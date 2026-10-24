import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../config.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'screens2.dart';
import 'screens4.dart';
import 'fx.dart';
import 'screens5.dart';
import 'screens7.dart';
import 'auth_screens.dart';
import 'map_screen.dart';
import '../i18n.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'widgets.dart';
import 'mascot.dart';

Widget _promo(BuildContext context, String title, String text, String cta, IconData icon, VoidCallback onTap) => Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(28)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.ink)),
        const SizedBox(height: 6),
        Text(text, style: const TextStyle(fontSize: 16, color: C.green, height: 1.4, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        PrimaryButton(label: cta, icon: icon, onPressed: onTap),
      ]),
    );

Widget _mapButton(BuildContext context, String kind) => Pressable(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapScreen(kind: kind))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.map_outlined, color: C.ink, size: 20),
          const SizedBox(width: 8),
          Text(tr('Carte'), style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
        ]),
      ),
    );

Widget _notConfigured() => const EmptyState(title: 'En attente de configuration', text: "Le serveur n'est pas encore connecté. Ajoutez SUPABASE_URL et SUPABASE_ANON_KEY dans les secrets GitHub, puis relancez le build.");

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});
  @override
  State<MarketplaceScreen> createState() => _MarketplaceState();
}

class _MarketplaceState extends State<MarketplaceScreen> {
  String? cat;
  String sort = 'recent';
  bool nearby = false;
  String? audienceFilter;
  Position? me;
  final minC = TextEditingController(), maxC = TextEditingController();
  late final Future<List<Map<String, dynamic>>> cats = Repo.categories();
  Future<List<Map<String, dynamic>>>? f;
  String lastQ = '\u0000';
  Timer? searchDebounce;

  int? minor(TextEditingController c) {
    final v = double.tryParse(c.text.replaceAll(',', '.'));
    return v == null ? null : (v * 100).round();
  }

  Future<List<Map<String, dynamic>>> load(String q) async {
    final items = await Repo.products(source: 'marketplace', q: q, categoryId: cat, minMinor: minor(minC), maxMinor: minor(maxC), sort: sort, limit: 60, audience: audienceFilter);
    if (me != null) {
      for (final p in items) {
        final sh = p['shops'] as Map?;
        final la = sh?['lat'], ln = sh?['lng'];
        if (la != null && ln != null) p['_dist'] = distKm(me!.latitude, me!.longitude, (la as num).toDouble(), (ln as num).toDouble());
      }
      if (nearby) items.sort((a, b) => ((a['_dist'] as double?) ?? 1e9).compareTo((b['_dist'] as double?) ?? 1e9));
    }
    return items;
  }

  void refresh() => setState(() => f = load(Repo.search.value));

  void liveSearch(String value) {
    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 350), () { if (mounted) Repo.search.value = value; });
  }

  Widget chip(String label, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: sel, onSelected: (_) => onTap()),
      );

  Future<void> toggleNearby(bool v) async {
    if (v && me == null) {
      final p = await myPosition(context);
      if (p == null) return;
      me = p;
    }
    nearby = v;
    refresh();
  }

  @override
  void dispose() { searchDebounce?.cancel(); minC.dispose(); maxC.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: Repo.search,
        builder: (_, q, __) {
          if (q != lastQ) {
            lastQ = q;
            f = load(q);
          }
          return ListView(padding: const EdgeInsets.all(18), children: [
            MascotHeader(mascot: Mascot.boutiques, title: tr('Marketplace'), subtitle: 'Produits des boutiques professionnelles vérifiées.', action: _mapButton(context, 'pro')),
            const SizedBox(height: 8),
            _promo(context, tr('Vous êtes commerçant ?'), 'Boutique professionnelle : 20 USD / mois. Vitrine, stock, commandes et livraison HAITIKET.', tr('Ouvrir ma boutique'), Icons.storefront, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopRequestScreen()))),
            SearchPill(onChanged: liveSearch, onSubmit: (v) { searchDebounce?.cancel(); Repo.search.value = v; }),
            if (q.trim().length >= 2) FutureBuilder<List<Map<String, dynamic>>>(
              future: Repo.searchShops(q),
              builder: (_, shopsState) {
                final shops = shopsState.data ?? const <Map<String, dynamic>>[];
                if (shops.isEmpty) return const SizedBox.shrink();
                return Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Boutiques correspondantes', style: TextStyle(fontWeight: FontWeight.w800)),
                  for (final shop in shops) ListTile(dense: true, leading: const Icon(Icons.storefront_outlined, color: C.terracotta), title: Text('${shop['name']}'), subtitle: Text('${shop['city'] ?? 'Haïti'}${shop['is_official'] == true ? ' · Boutique officielle HAITIKET' : ''}'), trailing: const Icon(Icons.north_east), onTap: () { Repo.search.value = ''; Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(shop['id'] as String))); }),
                ])));
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: cats,
                builder: (_, s) => ListView(scrollDirection: Axis.horizontal, children: [
                  chip(tr('Toutes'), cat == null, () {
                    cat = null;
                    refresh();
                  }),
                  for (final c in s.data ?? [])
                    chip('${c['name']}', cat == c['id'], () {
                      cat = c['id'] as String;
                      refresh();
                    }),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Public concerné', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              chip('Tous', audienceFilter == null, () { audienceFilter = null; refresh(); }),
              for (final audience in const ['Homme', 'Femme', 'Enfant', 'Adolescent', 'Unisexe'])
                chip(audience, audienceFilter == audience, () { audienceFilter = audience; refresh(); }),
            ])),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: minC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Prix min (HTG)', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: maxC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Prix max (HTG)', isDense: true))),
              IconButton(onPressed: refresh, icon: const Icon(Icons.check_circle, color: C.green, size: 32)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              DropdownButton<String>(
                value: sort,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: 'recent', child: Text(tr('Plus récents'))),
                  DropdownMenuItem(value: 'price_asc', child: Text(tr('Prix croissant'))),
                  DropdownMenuItem(value: 'price_desc', child: Text(tr('Prix décroissant'))),
                ],
                onChanged: (v) {
                  sort = v ?? 'recent';
                  refresh();
                },
              ),
              const Spacer(),
              FilterChip(avatar: const Icon(Icons.near_me, size: 18), label: Text(tr('Près de moi')), selected: nearby, onSelected: toggleNearby),
            ]),
            if (q.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Résultats pour « $q »', style: const TextStyle(color: C.muted, fontWeight: FontWeight.w700))),
            const SizedBox(height: 14),
            if (!Config.configured)
              _notConfigured()
            else
              FutureBuilder<List<Map<String, dynamic>>>(
                future: f,
                builder: (_, s) {
                  if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (s.hasError) return ErrorState(s.error);
                  final items = s.data ?? [];
                  if (items.isEmpty) return EmptyState(title: q.isEmpty ? 'Aucun produit trouvé' : 'Aucun résultat', text: 'Modifiez vos filtres ou votre recherche. Seuls les produits réellement en stock sont affichés.');
                  return ProductGrid(items);
                },
              ),
          ]);
        },
      );
}

class BazarScreen extends StatefulWidget {
  const BazarScreen({super.key});
  @override
  State<BazarScreen> createState() => _BazarState();
}

class _BazarState extends State<BazarScreen> {
  bool nearby = false;
  Position? me;
  late Future<List<Map<String, dynamic>>> f = load();

  Future<List<Map<String, dynamic>>> load() async {
    final items = await Repo.products(source: 'bazar', limit: 60);
    if (me != null) {
      for (final p in items) {
        final sh = p['shops'] as Map?;
        final la = sh?['lat'], ln = sh?['lng'];
        if (la != null && ln != null) p['_dist'] = distKm(me!.latitude, me!.longitude, (la as num).toDouble(), (ln as num).toDouble());
      }
      if (nearby) items.sort((a, b) => ((a['_dist'] as double?) ?? 1e9).compareTo((b['_dist'] as double?) ?? 1e9));
    }
    return items;
  }

  Future<void> toggleNearby(bool v) async {
    if (v && me == null) {
      final p = await myPosition(context);
      if (p == null) return;
      me = p;
    }
    setState(() {
      nearby = v;
      f = load();
    });
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async {
          setState(() => f = load());
          await f;
        },
        child: ListView(padding: const EdgeInsets.all(18), children: [
          MascotHeader(mascot: Mascot.bazar, title: 'Bazar', subtitle: 'Achetez et vendez entre particuliers : paiement et livraison HAITIKET comme en boutique.', action: _mapButton(context, 'personal')),
          const SizedBox(height: 8),
          _promo(context, tr('Vous êtes particulier ?'), 'Publiez votre article : 2 USD pour 14 jours, sans boutique professionnelle.', tr('Publier une annonce'), Icons.local_offer, () => startBazarListing(context)),
          Align(alignment: Alignment.centerRight, child: FilterChip(avatar: const Icon(Icons.near_me, size: 18), label: Text(tr('Près de moi')), selected: nearby, onSelected: toggleNearby)),
          const SizedBox(height: 12),
          if (!Config.configured)
            _notConfigured()
          else
            FutureBuilder<List<Map<String, dynamic>>>(
              future: f,
              builder: (_, s) {
                if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (s.hasError) return ErrorState(s.error);
                final items = s.data ?? [];
                if (items.isEmpty) return const EmptyState(title: "Aucune annonce pour l'instant", text: 'Publiez le premier article du Bazar.');
                return ProductGrid(items);
              },
            ),
        ]),
      );
}

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});
  @override
  State<NetworkScreen> createState() => _NetworkState();
}

class _NetworkState extends State<NetworkScreen> {
  final name = TextEditingController(), phone = TextEditingController(), zone = TextEditingController();
  String transport = 'moto';
  bool busy = false, kycBusy = false, kycSubmitted = false;
  DateTime? birthDate, guardianBirthDate;
  String documentType = 'cin_ninu';
  String? identityPath, birthCertificatePath, guardianDocumentPath, recentPhotoPath;
  final guardianName = TextEditingController();
  int? get calculatedAge {
    if (birthDate == null) return null;
    final now = DateTime.now();
    var age = now.year - birthDate!.year;
    if (now.month < birthDate!.month || (now.month == birthDate!.month && now.day < birthDate!.day)) age--;
    return age;
  }

  Future<String?> pickKycImage(String kind, {bool camera = false}) async {
    final user = currentUser();
    if (user == null) { toast(context, 'Connectez-vous pour téléverser les documents.'); return null; }
    final picker = ImagePicker();
    final file = await picker.pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, imageQuality: 88, maxWidth: 2200);
    if (file == null) return null;
    final ext0 = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
    final ext = ['jpg', 'jpeg', 'png', 'webp'].contains(ext0) ? ext0 : 'jpg';
    final mime = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
    final path = '${user.id}/${DateTime.now().microsecondsSinceEpoch}_$kind.$ext';
    await Supabase.instance.client.storage.from('kyc-private').uploadBinary(path, await file.readAsBytes(), fileOptions: FileOptions(contentType: mime, upsert: false));
    return path;
  }

  Future<void> chooseBirthDate({required bool guardian}) async {
    final initial = guardian ? (guardianBirthDate ?? DateTime(1980, 1, 1)) : (birthDate ?? DateTime(2000, 1, 1));
    final value = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(1900), lastDate: DateTime.now());
    if (value == null) return;
    setState(() { if (guardian) { guardianBirthDate = value; } else { birthDate = value; if ((calculatedAge ?? 18) >= 18 && !['cin_ninu','passport','drivers_license'].contains(documentType)) documentType = 'cin_ninu'; } });
  }

  Future<void> submitKyc() async {
    if (birthDate == null || recentPhotoPath == null) return toast(context, 'Date de naissance et photo récente obligatoires.');
    final age = calculatedAge ?? -1;
    if (age >= 18 && identityPath == null) return toast(context, 'Ajoutez une CIN/NINU, un passeport ou un permis.');
    if (age < 18 && (birthCertificatePath == null || guardianDocumentPath == null || guardianName.text.trim().length < 3 || guardianBirthDate == null)) return toast(context, 'Pour un mineur : acte de naissance, responsable majeur, date de naissance et pièce du responsable sont obligatoires.');
    setState(() => kycBusy = true);
    try {
      await Repo.submitIdentityVerification(dateOfBirth: birthDate!, documentType: age >= 18 ? documentType : 'minor_guardian',
        identityDocumentPath: identityPath, birthCertificatePath: birthCertificatePath, guardianName: guardianName.text.trim(),
        guardianDateOfBirth: guardianBirthDate, guardianDocumentPath: guardianDocumentPath, recentPhotoPath: recentPhotoPath!);
      if (mounted) { setState(() => kycSubmitted = true); toast(context, 'Dossier KYC envoyé à l’administration pour vérification.'); }
    } catch (e) { if (mounted) toast(context, Repo.err(e)); }
    if (mounted) setState(() => kycBusy = false);
  }

  Future<void> submit() async {
    if (name.text.trim().isEmpty || phone.text.trim().isEmpty || zone.text.trim().isEmpty) return toast(context, 'Remplissez tous les champs.');
    setState(() => busy = true);
    try {
      await Repo.applyCourier(name.text.trim(), phone.text.trim(), transport, zone.text.trim());
      if (mounted) toast(context, 'Candidature envoyée. Vous serez contacté après vérification.');
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        MascotHeader(mascot: Mascot.orders, title: 'HAITIKET Network', subtitle: 'Devenez livreur indépendant. Chaque mission affiche votre rémunération avant acceptation.'),
        Field(name, 'Nom complet'),
        Field(phone, 'Téléphone', type: TextInputType.phone),
        DropdownButtonFormField<String>(
          initialValue: transport,
          decoration: const InputDecoration(labelText: 'Moyen de transport'),
          items: const [
            DropdownMenuItem(value: 'pied', child: Text('À pied')),
            DropdownMenuItem(value: 'velo', child: Text('Vélo')),
            DropdownMenuItem(value: 'moto', child: Text('Moto')),
            DropdownMenuItem(value: 'voiture', child: Text('Voiture')),
            DropdownMenuItem(value: 'camionnette', child: Text('Camionnette')),
          ],
          onChanged: (v) => setState(() => transport = v ?? 'moto'),
        ),
        const SizedBox(height: 12),
        Field(zone, "Zone d'activité (ex. Delmas)"),
        const SizedBox(height: 20),
        const Text('Vérification d’identité KYC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.ink)),
        const Text('Obligatoire avant l’approbation comme livreur et pour obtenir le badge de boutique vérifiée. Les documents sont privés et examinés par l’administration.'),
        OutlinedButton.icon(onPressed: () => chooseBirthDate(guardian: false), icon: const Icon(Icons.cake_outlined), label: Text(birthDate == null ? 'Choisir ma date de naissance' : 'Date de naissance : ${birthDate!.year}-${birthDate!.month.toString().padLeft(2, '0')}-${birthDate!.day.toString().padLeft(2, '0')}')),
        if (calculatedAge != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Âge calculé : $calculatedAge ans${calculatedAge! < 18 ? ' · dossier mineur' : ' · dossier majeur'}', style: const TextStyle(fontWeight: FontWeight.w700))),
        if (calculatedAge == null || calculatedAge! >= 18) ...[
          DropdownButtonFormField<String>(initialValue: documentType, decoration: const InputDecoration(labelText: 'Type de pièce officielle'), items: const [DropdownMenuItem(value: 'cin_ninu', child: Text('CIN / NINU')), DropdownMenuItem(value: 'passport', child: Text('Passeport')), DropdownMenuItem(value: 'drivers_license', child: Text('Permis de conduire'))], onChanged: (v) => setState(() => documentType = v ?? 'cin_ninu')),
          OutlinedButton.icon(onPressed: () async { try { final p = await pickKycImage('identite'); if (p != null) setState(() => identityPath = p); } catch (e) { if (mounted) toast(context, Repo.err(e)); } }, icon: const Icon(Icons.badge_outlined), label: Text(identityPath == null ? 'Photographier / choisir la pièce d’identité' : 'Pièce d’identité ajoutée ✓')),
        ],
        if (calculatedAge != null && calculatedAge! < 18) ...[
          OutlinedButton.icon(onPressed: () async { try { final p = await pickKycImage('acte_naissance'); if (p != null) setState(() => birthCertificatePath = p); } catch (e) { if (mounted) toast(context, Repo.err(e)); } }, icon: const Icon(Icons.description_outlined), label: Text(birthCertificatePath == null ? 'Ajouter l’acte de naissance' : 'Acte de naissance ajouté ✓')),
          Field(guardianName, 'Nom complet du responsable majeur'),
          OutlinedButton.icon(onPressed: () => chooseBirthDate(guardian: true), icon: const Icon(Icons.cake), label: Text(guardianBirthDate == null ? 'Date de naissance du responsable' : 'Naissance responsable : ${guardianBirthDate!.year}-${guardianBirthDate!.month.toString().padLeft(2, '0')}-${guardianBirthDate!.day.toString().padLeft(2, '0')}')),
          OutlinedButton.icon(onPressed: () async { try { final p = await pickKycImage('piece_responsable'); if (p != null) setState(() => guardianDocumentPath = p); } catch (e) { if (mounted) toast(context, Repo.err(e)); } }, icon: const Icon(Icons.family_restroom), label: Text(guardianDocumentPath == null ? 'Ajouter la pièce du responsable' : 'Pièce du responsable ajoutée ✓')),
        ],
        OutlinedButton.icon(onPressed: () async { try { final p = await pickKycImage('photo_recente', camera: true); if (p != null) setState(() => recentPhotoPath = p); } catch (e) { if (mounted) toast(context, Repo.err(e)); } }, icon: const Icon(Icons.camera_alt_outlined), label: Text(recentPhotoPath == null ? 'Prendre une photo récente de moi' : 'Photo récente ajoutée ✓')),
        FilledButton.tonal(onPressed: kycBusy || kycSubmitted ? null : submitKyc, child: Text(kycSubmitted ? 'Dossier KYC envoyé' : kycBusy ? 'Envoi du dossier…' : 'Envoyer le dossier KYC à l’administration')),
        const SizedBox(height: 12),
        FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Envoi…' : 'Envoyer ma candidature')),
        const SizedBox(height: 16),
        const EmptyState(title: 'Missions', text: "Les missions seront proposées après vérification de votre profil. Aucun livreur n'est affiché tant qu'il n'est pas réellement validé."),
      ]);
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        MascotHeader(mascot: Mascot.badge, title: tr('Favoris'), subtitle: 'Vos coups de cœur, gardés pour plus tard.'),
        if (currentUser() == null)
          const EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour retrouver vos favoris sur tous vos appareils.')
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            future: Repo.favorites(),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              final items = s.data ?? [];
              if (items.isEmpty) return const EmptyState(title: 'Aucun favori', text: 'Touchez le cœur sur un produit pour le garder ici.');
              return ProductGrid(items);
            },
          ),
      ]);
}

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: CartStore.lines,
        builder: (_, lines, __) {
          final l = lines.values.toList();
          final total = CartStore.totalMinor;
          return ListView(padding: const EdgeInsets.all(18), children: [
            MascotHeader(mascot: Mascot.cart, title: tr('Panier')),
            if (l.isEmpty)
              const EmptyState(title: 'Votre panier est vide', text: 'Ajoutez des produits depuis la Marketplace.')
            else ...[
              for (final x in l)
                Card(
                  color: Colors.white,
                  child: ListTile(
                    title: Text(x.variantLabel == null ? x.name : '${x.name} (${x.variantLabel})', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${money(CartStore.unitFor(x), x.currency)} / unité${CartStore.unitFor(x) < x.basePrice ? ' · tarif quantité' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(onPressed: () => CartStore.change(x.key, -1), icon: const Icon(Icons.remove_circle_outline)),
                      Text('${x.qty}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      IconButton(onPressed: () => CartStore.change(x.key, 1), icon: const Icon(Icons.add_circle_outline)),
                    ]),
                  ),
                ),
              const SizedBox(height: 12),
              Text('Total estimé : ${money(total, l.first.currency)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.ink)),
              const SizedBox(height: 4),
              const Text('Le total final est recalculé par le serveur (livraison, frais, réductions).', style: TextStyle(color: C.muted)),
              const SizedBox(height: 16),
              PrimaryButton(label: tr('Passer commande'), icon: Icons.lock_outline, onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckoutScreen()))),
              const SizedBox(height: 8),
              const Text('Paiement indisponible — en attente de configuration du prestataire.', style: TextStyle(color: C.terracotta, fontWeight: FontWeight.w700)),
            ],
          ]);
        },
      );
}

class AccountScreen extends StatelessWidget {
  final VoidCallback onChanged;
  const AccountScreen({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final u = currentUser();
    return ListView(padding: const EdgeInsets.all(18), children: [
      MascotHeader(mascot: u == null ? Mascot.welcome : Mascot.profile, title: u == null ? 'Bienvenue' : 'Mon compte', subtitle: u == null ? 'Connectez-vous ou créez votre compte HAITIKET.' : null),
      if (!Config.configured)
        _notConfigured()
      else if (u != null) ...[
        Text(u.email ?? '', style: const TextStyle(fontSize: 18, color: C.ink)),
        const SizedBox(height: 8),
        const Text('Retrouvez votre profil, vos adresses et la suppression de compte dans « Mon profil » (menu).', style: TextStyle(color: C.muted)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            await Repo.signOut();
            onChanged();
          },
          child: const Text('Se déconnecter'),
        ),
      ] else
        AuthPanel(onChanged: onChanged),
    ]);
  }
}
