import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';

@pragma('vm:entry-point')
Future<void> haitiketBackgroundHandler(RemoteMessage message) async {
  // Le système affiche lui-même la notification (bloc « notification » envoyé par send-push).
}

/// Notifications push système (FCM). Inactif tant que les secrets FIREBASE_* ne sont pas fournis au build,
/// et inactif sur le Web. Le jeton de l'appareil est enregistré côté serveur (RPC register_push_token).
class PushService {
  static bool _ready = false;
  static StreamSubscription<String>? _refreshSub;

  static Future<void> init() async {
    if (_ready || kIsWeb || !Config.pushConfigured || !Config.configured) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: Config.firebaseApiKey,
            appId: Config.firebaseAppId,
            messagingSenderId: Config.firebaseSenderId,
            projectId: Config.firebaseProjectId,
          ),
        );
      }
      FirebaseMessaging.onBackgroundMessage(haitiketBackgroundHandler);
      final fm = FirebaseMessaging.instance;
      final perm = await fm.requestPermission(alert: true, badge: true, sound: true);
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await fm.getToken();
      if (token != null) await _register(token);
      _refreshSub ??= fm.onTokenRefresh.listen(_register);
      _ready = true;
    } catch (e) {
      debugPrint('Push non initialisé : $e');
    }
  }

  static Future<void> _register(String token) async {
    try {
      await Supabase.instance.client.rpc('register_push_token', params: {'p_token': token, 'p_platform': defaultTargetPlatform.name});
    } catch (e) {
      debugPrint('Enregistrement du jeton push impossible : $e');
    }
  }

  /// À appeler à la déconnexion : l'appareil ne doit plus recevoir les alertes de l'ancien compte.
  static Future<void> unregister() async {
    if (!_ready) return;
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) await Supabase.instance.client.rpc('unregister_push_token', params: {'p_token': t});
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _ready = false;
  }
}
