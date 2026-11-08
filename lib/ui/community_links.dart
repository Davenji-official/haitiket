import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';

const kTelegramUrl = 'https://t.me/haitiket';
const kWhatsappChannelUrl = 'https://whatsapp.com/channel/0029VbE65tb1XquOuQVEBr2A';

Future<void> _open(BuildContext c, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir le lien.")));
}

/// Invitation à suivre HAITIKET sur Telegram et sur la chaîne WhatsApp (accueil, menu, profil).
class CommunityLinks extends StatelessWidget {
  final bool compact;
  const CommunityLinks({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final buttons = Wrap(spacing: 10, runSpacing: 8, children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF229ED9), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
        onPressed: () => _open(context, kTelegramUrl),
        icon: const Icon(Icons.send_rounded, size: 18),
        label: const Text('Telegram'),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
        onPressed: () => _open(context, kWhatsappChannelUrl),
        icon: const Icon(Icons.campaign_rounded, size: 18),
        label: const Text('Chaîne WhatsApp'),
      ),
    ]);
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Suivez HAITIKET', style: TextStyle(fontWeight: FontWeight.w900, color: C.ink)),
          const SizedBox(height: 6),
          buttons,
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Rejoignez la communauté HAITIKET', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: C.ink)),
        const SizedBox(height: 4),
        Text('Nouveautés, promotions, annonces et bons plans en direct. Rejoignez-nous sur nos canaux officiels.', style: TextStyle(color: C.muted)),
        const SizedBox(height: 10),
        buttons,
      ]),
    );
  }
}
