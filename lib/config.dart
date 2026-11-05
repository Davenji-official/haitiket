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

// Firebase (notifications push) : valeurs fournies au build par --dart-define (secrets GitHub FIREBASE_*).
static const String firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
static const String firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
static const String firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
static bool get pushConfigured =>
firebaseApiKey.isNotEmpty && firebaseAppId.isNotEmpty && firebaseSenderId.isNotEmpty && firebaseProjectId.isNotEmpty;
}
