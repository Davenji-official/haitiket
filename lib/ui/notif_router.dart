import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/repo.dart';
import 'product_detail.dart';
import 'screens2.dart';
import 'screens3.dart';
import 'screens5.dart';

/// Clé de navigation globale : permet d'ouvrir un écran depuis une notification (liste ou push), sans contexte.
final GlobalKey<NavigatorState> appNavKey = GlobalKey<NavigatorState>();

/// Demande de changement de section du menu principal (écoutée par Shell). Valeur = nom d'une section (ex. « wallet »).
class ShellNav {
  static final ValueNotifier<String?> request = ValueNotifier<String?>(null);
  static void go(String section) => request.value = section;
}

SupabaseClient get _db => Supabase.instance.client;

/// Ouvre l'endroit précis lié à une notification : produit, boutique, commande, conversation, portefeuille, mission…
Future<void> openNotificationTarget({required String kind, String? ref, String? link}) async {
  final nav = appNavKey.currentState;
  if (nav == null) return;
  final cleanRef = (ref == null || ref.isEmpty || ref == 'null') ? null : ref;
  final cleanLink = (link == null || link.isEmpty || link == 'null') ? null : link;

  Future<bool> openProduct(String id) async {
    try {
      final p = await Repo.productById(id, requireStock: false);
      nav.push(MaterialPageRoute<void>(builder: (_) => ProductDetailScreen(p)));
      return true;
    } catch (_) {
      return false;
    }
  }

  // 1. Lien explicite (diffusion admin, push) : produit HAITIKET ou lien externe.
  if (cleanLink != null && cleanLink.startsWith('https://')) {
    final u = Uri.tryParse(cleanLink);
    final pid = u?.queryParameters['product'];
    if (pid != null && await openProduct(pid)) return;
    await launchUrl(Uri.parse(cleanLink), mode: LaunchMode.externalApplication);
    return;
  }

  switch (kind) {
    case 'order':
    case 'offer':
      if (cleanRef != null) {
        try {
          final o = await _db.from('orders').select('id,customer_id,shops(name)').eq('id', cleanRef).maybeSingle();
          final me = _db.auth.currentUser?.id;
          if (o != null && o['customer_id'] == me) {
            nav.push(MaterialPageRoute<void>(builder: (_) => OrderTrackingScreen(orderId: cleanRef, shopName: '${(o['shops'] as Map?)?['name'] ?? 'Boutique'}')));
            return;
          }
        } catch (_) {}
      }
      ShellNav.go('dashboard'); // vendeur : tableau de bord des commandes
      return;
    case 'job':
    case 'courier':
      ShellNav.go('courier');
      return;
    case 'message':
    case 'mention':
      if (cleanRef != null) {
        nav.push(MaterialPageRoute<void>(builder: (_) => ChatScreen(cleanRef)));
      } else {
        ShellNav.go('messages');
      }
      return;
    case 'wallet':
      ShellNav.go('wallet');
      return;
    case 'support':
      ShellNav.go('support');
      return;
    case 'shop':
      if (cleanRef != null) {
        try {
          final s = await _db.from('shops').select('id').eq('id', cleanRef).maybeSingle();
          if (s != null) {
            nav.push(MaterialPageRoute<void>(builder: (_) => ShopScreen(cleanRef)));
            return;
          }
        } catch (_) {}
      }
      ShellNav.go('dashboard');
      return;
    case 'listing':
    case 'product':
      if (cleanRef != null && await openProduct(cleanRef)) return;
      ShellNav.go('bazar');
      return;
    default:
      ShellNav.go('notifications');
  }
}
