import 'package:flutter/material.dart';
import '../config.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'fx.dart';
import 'widgets.dart';

Widget _h(String t) => Padding(padding: const EdgeInsets.only(bottom: 18), child: Text(t, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1)));

Widget _info(String t) => Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.mint.withValues(alpha: .6), borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: const TextStyle(color: C.ink, fontSize: 16, height: 1.4, fontWeight: FontWeight.w600)),
    );

/// Boutique professionnelle : 20 USD / mois (Marketplace).
class ShopRequestScreen extends StatefulWidget {
  const ShopRequestScreen({super.key});
  @override
  State<ShopRequestScreen> createState() => _ShopRequestState();
}

class _ShopRequestState extends State<ShopRequestScreen> {
  final name = TextEditingController(), city = TextEditingController();
  bool busy = false;

  Future<void> submit() async {
    if (name.text.trim().length < 2) return toast(context, 'Indiquez le nom de la boutique.');
    setState(() => busy = true);
    try {
      await Repo.createShop(name.text.trim(), city.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, 'Demande envoyée. Votre boutique sera activée après vérification.');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Boutique professionnelle', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          _info("Abonnement : 20 USD par mois. Vitrine dans la Marketplace, gestion du stock, commandes et livraison HAITIKET. Votre boutique est vérifiée avant activation. Le paiement de l'abonnement est indisponible pour le moment (prestataire en attente de configuration)."),
          Field(name, 'Nom de la boutique'),
          Field(city, 'Ville'),
          PrimaryButton(label: busy ? 'Envoi…' : "Demander l'ouverture", icon: Icons.storefront, onPressed: busy ? null : submit),
        ]),
      );
}

/// Annonce Bazar : 2 USD pour 14 jours.
class ListingFormScreen extends StatefulWidget {
  const ListingFormScreen({super.key});
  @override
  State<ListingFormScreen> createState() => _ListingFormState();
}

class _ListingFormState extends State<ListingFormScreen> {
  final title = TextEditingController(), price = TextEditingController(), city = TextEditingController();
  String? img;
  bool busy = false;

  Future<void> submit() async {
    final p = double.tryParse(price.text.replaceAll(',', '.'));
    if (title.text.trim().isEmpty || p == null || p <= 0) return toast(context, 'Titre et prix valides requis.');
    setState(() => busy = true);
    try {
      await Repo.createListingDraft(title.text.trim(), (p * 100).round(), city.text.trim(), img);
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, 'Brouillon enregistré.');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Publier au Bazar', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          _info("2 USD pour 14 jours, renouvelable. Sans renouvellement, l'annonce est bloquée puis supprimée du catalogue après 30 jours. Le paiement est indisponible pour le moment : votre annonce reste en brouillon."),
          Field(title, "Titre de l'article"),
          Field(price, 'Prix en HTG', type: TextInputType.number),
          Field(city, 'Ville'),
          ImageUploadField(onUrl: (u) => img = u),
          PrimaryButton(label: busy ? 'Enregistrement…' : 'Enregistrer le brouillon', icon: Icons.local_offer, onPressed: busy ? null : submit),
        ]),
      );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends State<ProfileScreen> {
  final name = TextEditingController(), phone = TextEditingController();
  String? avatar;
  bool loading = true, busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (currentUser() == null) {
      setState(() => loading = false);
      return;
    }
    try {
      final p = await Repo.getProfile();
      name.text = (p?['display_name'] ?? '') as String;
      phone.text = (p?['phone'] ?? '') as String;
      avatar = p?['avatar_url'] as String?;
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await Repo.saveProfile(name.text.trim(), phone.text.trim(), avatar);
      if (mounted) toast(context, 'Profil enregistré.');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        _h('Mon profil'),
        if (currentUser() == null || !Config.configured)
          const EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour gérer votre profil.')
        else if (loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          Center(child: CircleAvatar(radius: 48, backgroundColor: C.mint, backgroundImage: avatar == null ? null : NetworkImage(avatar!), child: avatar == null ? const Icon(Icons.person, size: 48, color: C.green) : null)),
          const SizedBox(height: 14),
          ImageUploadField(onUrl: (u) => setState(() => avatar = u)),
          Field(name, "Nom d'affichage"),
          Field(phone, 'Téléphone', type: TextInputType.phone),
          const Text("Votre téléphone n'est jamais public.", style: TextStyle(color: C.muted)),
          const SizedBox(height: 16),
          PrimaryButton(label: busy ? 'Enregistrement…' : 'Enregistrer', icon: Icons.check, onPressed: busy ? null : save),
        ],
      ]);
}

class SettingsScreen extends StatelessWidget {
  final VoidCallback onChanged;
  const SettingsScreen({super.key, required this.onChanged});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        _h('Paramètres'),
        const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.language, color: C.green), title: Text('Langue', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('Français (actif) · Kreyòl ayisyen : bientôt disponible'), trailing: Icon(Icons.check_circle, color: C.green)),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.shopping_bag_outlined, color: C.green),
          title: const Text('Vider mon panier', style: TextStyle(fontWeight: FontWeight.w700)),
          onTap: () {
            CartStore.lines.value = {};
            toast(context, 'Panier vidé.');
          },
        ),
        const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.lock_outline, color: C.green), title: Text('Confidentialité', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('Adresse et téléphone : visibles uniquement par les parties d\'une commande.')),
        const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.info_outline, color: C.green), title: Text('Version', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('HAITIKET 0.6')),
      ]);
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportState();
}

class _SupportState extends State<SupportScreen> {
  final subject = TextEditingController(), message = TextEditingController();
  late Future<List<Map<String, dynamic>>> f = Repo.myTickets();
  bool busy = false;

  Future<void> send() async {
    if (subject.text.trim().length < 3 || message.text.trim().length < 5) return toast(context, 'Sujet et message trop courts.');
    setState(() => busy = true);
    try {
      await Repo.createTicket(subject.text.trim(), message.text.trim());
      subject.clear();
      message.clear();
      f = Repo.myTickets();
      if (mounted) toast(context, 'Demande envoyée au support.');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        _h('Support'),
        const ExpansionTile(title: Text('Comment fonctionne le paiement ?', style: TextStyle(fontWeight: FontWeight.w700)), children: [Padding(padding: EdgeInsets.all(14), child: Text("Le paiement en ligne sera activé dès qu'un prestataire sera connecté. Jusqu'là, les commandes restent en attente de paiement."))]),
        const ExpansionTile(title: Text('Combien coûte vendre ?', style: TextStyle(fontWeight: FontWeight.w700)), children: [Padding(padding: EdgeInsets.all(14), child: Text("Bazar : 2 USD pour 14 jours. Boutique professionnelle : 20 USD par mois. Commission de 2 % sur les ventes."))]),
        const ExpansionTile(title: Text('Comment devenir livreur ?', style: TextStyle(fontWeight: FontWeight.w700)), children: [Padding(padding: EdgeInsets.all(14), child: Text("Déposez votre candidature dans HAITIKET Network. Elle est vérifiée avant l'accès aux missions."))]),
        const SizedBox(height: 18),
        if (currentUser() == null || !Config.configured)
          const EmptyState(title: 'Connexion requise', text: 'Connectez-vous pour contacter le support.')
        else ...[
          const Text('Contacter le support', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.ink)),
          const SizedBox(height: 12),
          Field(subject, 'Sujet'),
          Field(message, 'Votre message'),
          PrimaryButton(label: busy ? 'Envoi…' : 'Envoyer', icon: Icons.send, onPressed: busy ? null : send),
          const SizedBox(height: 24),
          const Text('Mes demandes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.ink)),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: f,
            builder: (_, s) {
              final items = s.data ?? [];
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (items.isEmpty) return const Text('Aucune demande.', style: TextStyle(color: C.muted));
              return Column(children: [
                for (final t in items)
                  Card(
                    color: Colors.white,
                    child: ListTile(
                      title: Text('${t['subject']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(t['admin_reply'] != null ? 'Réponse : ${t['admin_reply']}' : 'En attente de réponse · ${t['status']}'),
                    ),
                  ),
              ]);
            },
          ),
        ],
      ]);
}
