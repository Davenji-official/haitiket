class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get configured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
