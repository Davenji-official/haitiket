import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import 'widgets.dart';

/// Les guides PDF sont hébergés dans le dépôt public (dossier « guides »).
const kGuidesBase = 'https://davenji-official.github.io/haitiket/guides/';
const kGuidesFallback = 'https://github.com/Davenji-official/haitiket/raw/main/guides/';

class _Guide {
  final String file, title, text;
  final IconData icon;
  const _Guide(this.file, this.title, this.text, this.icon);
}

class GuidesScreen extends StatelessWidget {
  const GuidesScreen({super.key});

  static const _items = [
    _Guide('client', 'Client', 'Acheter, payer avec le portefeuille, suivre la commande, donner le code de remise, être remboursé en cas de retard.', Icons.shopping_bag_outlined),
    _Guide('boutique_pro', 'Boutique professionnelle', 'Ouvrir une boutique, abonnement, produits, commandes, argent et fermeture.', Icons.storefront_outlined),
    _Guide('vendeur_particulier_bazar', 'Vendeur particulier (Bazar)', 'Publier une annonce, la payer, vendre et être payé.', Icons.campaign_outlined),
    _Guide('livreur', 'Livreur', 'Candidature, missions, codes de collecte et de remise, retard de trafic, paiement.', Icons.two_wheeler_outlined),
  ];

  Future<void> _open(BuildContext c, String file, String lang) async {
    var ok = false;
    for (final base in const [kGuidesBase, kGuidesFallback]) {
      try {
        ok = await launchUrl(Uri.parse('${base}guide_${file}_$lang.pdf'), mode: LaunchMode.externalApplication);
      } catch (_) {
        ok = false;
      }
      if (ok) break;
    }
    if (!ok && c.mounted) toast(c, "Impossible d'ouvrir le guide. Vérifiez votre connexion.");
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text("Guides d'utilisation", style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          Text('Choisissez votre guide, en français ou en kreyòl. Chaque guide s\'ouvre en PDF et contient des exemples.', style: TextStyle(color: C.muted, height: 1.4)),
          const SizedBox(height: 14),
          for (final g in _items)
            Card(
              color: C.card,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(g.icon, color: C.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(g.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: C.ink))),
                  ]),
                  const SizedBox(height: 6),
                  Text(g.text, style: TextStyle(color: C.muted)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => _open(context, g.file, 'fr'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Français'))),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton.icon(onPressed: () => _open(context, g.file, 'kr'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Kreyòl'))),
                  ]),
                ]),
              ),
            ),
        ]),
      );
}
