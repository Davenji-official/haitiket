import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';

SupabaseClient get _c => Supabase.instance.client;
User? currentUser() => Config.configured ? _c.auth.currentUser : null;
String money(num minor, String cur) => '${(minor / 100).toStringAsFixed(2)} $cur';

class CartLine {
  final String id, name, currency;
  final int priceMinor;
  int qty;
  CartLine(this.id, this.name, this.priceMinor, this.currency, this.qty);
}

class CartStore {
  static final lines = ValueNotifier<Map<String, CartLine>>({});
  static int get count => lines.value.values.fold(0, (a, l) => a + l.qty);
  static void add(Map<String, dynamic> p) {
    final m = Map<String, CartLine>.from(lines.value);
    final id = p['id'] as String;
    if (m.containsKey(id)) {
      m[id]!.qty++;
    } else {
      m[id] = CartLine(id, p['name'] as String, (p['price_minor'] as num).toInt(), (p['currency'] ?? 'HTG') as String, 1);
    }
    lines.value = m;
  }

  static void change(String id, int delta) {
    final m = Map<String, CartLine>.from(lines.value);
    final l = m[id];
    if (l == null) return;
    l.qty += delta;
    if (l.qty <= 0) m.remove(id);
    lines.value = m;
  }
}

class Repo {
  static final search = ValueNotifier<String>('');

  static Future<List<Map<String, dynamic>>> products({String q = '', int limit = 24}) async {
    if (!Config.configured) return [];
    var f = _c.from('products').select('id,name,price_minor,currency,image_url,stock,shops(name)').eq('status', 'published').gt('stock', 0);
    final t = q.trim().replaceAll(RegExp(r'[%,()]'), ' ');
    if (t.isNotEmpty) f = f.ilike('name', '%$t%');
    final rows = await f.order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> listings() async {
    if (!Config.configured) return [];
    final rows = await _c.from('listings').select('id,title,price_minor,currency,city,image_url,condition').eq('status', 'published').order('created_at', ascending: false).limit(40);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<int> activeShops() async {
    if (!Config.configured) return 0;
    final rows = await _c.from('shops').select('id').eq('status', 'active').limit(1000);
    return (rows as List).length;
  }

  static Future<List<Map<String, dynamic>>> favorites() async {
    final u = currentUser();
    if (u == null) return [];
    final rows = await _c.from('favorites').select('products(id,name,price_minor,currency,image_url,stock,shops(name))').eq('user_id', u.id);
    return [for (final r in rows) if (r['products'] != null) Map<String, dynamic>.from(r['products'] as Map)];
  }

  static Future<void> toggleFavorite(String productId) async {
    final u = currentUser();
    if (u == null) throw 'Connectez-vous pour utiliser les favoris.';
    final ex = await _c.from('favorites').select('product_id').eq('user_id', u.id).eq('product_id', productId);
    if ((ex as List).isEmpty) {
      await _c.from('favorites').insert({'user_id': u.id, 'product_id': productId});
    } else {
      await _c.from('favorites').delete().eq('user_id', u.id).eq('product_id', productId);
    }
  }

  static Future<void> createShop(String name, String city) async {
    final u = currentUser();
    if (u == null) throw 'Connectez-vous pour ouvrir une boutique.';
    await _c.from('shops').insert({'owner_id': u.id, 'name': name, 'city': city, 'status': 'pending'});
  }

  static Future<void> createListingDraft(String title, int priceMinor, String city) async {
    final u = currentUser();
    if (u == null) throw 'Connectez-vous pour publier une annonce.';
    await _c.from('listings').insert({'seller_id': u.id, 'title': title, 'price_minor': priceMinor, 'currency': 'HTG', 'city': city, 'status': 'draft'});
  }

  static Future<void> applyCourier(String name, String phone, String transport, String zone) async {
    final u = currentUser();
    if (u == null) throw 'Connectez-vous pour déposer une candidature.';
    await _c.from('courier_applications').insert({'user_id': u.id, 'full_name': name, 'phone': phone, 'transport': transport, 'zone': zone});
  }

  static Future<void> signIn(String email, String pass) => _c.auth.signInWithPassword(email: email, password: pass);
  static Future<void> signUp(String email, String pass) => _c.auth.signUp(email: email, password: pass);
  static Future<void> signOut() => _c.auth.signOut();
}
