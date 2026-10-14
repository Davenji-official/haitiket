class Config {
// URL du projet Supabase
static const String supabaseUrl =
'https://vuzspdewbvavjwowgurp.supabase.co';

// Clé publique Supabase
static const String supabaseAnonKey =
'sb_publishable_BiqqacKy77iDbT1iCFRcEA_hCvDc4Xd';

// Vérification de la configuration
static bool get configured =>
supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
