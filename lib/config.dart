class Config {
// URL du projet Supabase
static const String supabaseUrl =
'https://ntroqvxeotifsmdzrwyo.supabase.co';

// Clé publique Supabase
static const String supabaseAnonKey =
'sb_publishable_f4aIkGRm6kXmXjIMfOHrzA_6YwLUSz8';

// Vérification de la configuration
static bool get configured =>
supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
