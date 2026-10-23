import 'package:flutter_test/flutter_test.dart';
import 'package:haitiket/config.dart';

void main() {
  test('Supabase client configuration has a URL and a public key', () {
    expect(Uri.tryParse(Config.supabaseUrl)?.scheme, 'https');
    expect(Config.supabaseUrl, contains('.supabase.co'));
    expect(Config.supabaseAnonKey, isNotEmpty);
    expect(Config.supabaseAnonKey, isNot(contains('service_role')));
    expect(Config.supabaseAnonKey, isNot(contains('CLIENT_SECRET')));
  });
}
