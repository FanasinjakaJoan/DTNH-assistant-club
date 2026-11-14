/// Configuration de déploiement (valeurs par défaut compilées dans l'app).
///
/// Toutes les valeurs sont surchargeables au build sans toucher au code :
///
/// ```bash
/// flutter build web --release \
///   --dart-define=DTNH_SUPABASE_SYNC_URL="https://<ref>.supabase.co/functions/v1/dtnh-sync" \
///   --dart-define=DTNH_SUPABASE_SECRET="<secret partagé>"
/// ```
///
/// Le secret partagé n'est **pas** une clé Supabase : l'application n'a aucun
/// accès direct à PostgreSQL (RLS activée sans policy). Il sert uniquement à
/// authentifier les envois vers l'Edge Function, exactement comme le
/// `SHARED_SECRET` du webhook Apps Script. En cas de fuite, le pire scénario
/// est l'insertion de lignes parasites dans les tables `dtnh_*` : le secret se
/// régénère côté Supabase (secrets de la fonction) puis au build.
class AppConfig {
  const AppConfig._();

  /// Endpoint par défaut : Edge Function `dtnh-sync` du projet Supabase du club.
  static const String supabaseSyncUrl = String.fromEnvironment(
    'DTNH_SUPABASE_SYNC_URL',
    defaultValue:
        'https://osjsczvsnyknkdwbciab.supabase.co/functions/v1/dtnh-sync',
  );

  /// Secret partagé de l'Edge Function (`DTNH_SHARED_SECRET` côté Supabase).
  static const String supabaseSyncSecret = String.fromEnvironment(
    'DTNH_SUPABASE_SECRET',
    defaultValue: 'd15706a85d4a1e09e12fa8363cc43fb49fd86f289bf1b623',
  );

  /// Page de téléchargement de l'APK Android (artefacts GitHub Actions).
  static const String apkReleaseUrl = String.fromEnvironment(
    'DTNH_APK_URL',
    defaultValue:
        'https://github.com/FanasinjakaJoan/DTNH-assistant-club/releases/latest',
  );

  /// URL publique de l'application web (affichée dans l'écran d'installation).
  static const String webAppUrl = String.fromEnvironment(
    'DTNH_WEB_URL',
    defaultValue: 'https://dtnh-assistant-club.vercel.app',
  );

  /// Identifiant du projet Supabase (informatif, affiché dans les réglages).
  static const String supabaseProjectRef = 'osjsczvsnyknkdwbciab';

  /// URL du projet Supabase (Auth + REST).
  static const String supabaseUrl = String.fromEnvironment(
    'DTNH_SUPABASE_URL',
    defaultValue: 'https://osjsczvsnyknkdwbciab.supabase.co',
  );

  /// Clé **publishable** (anon) du projet. Publique par conception : elle est
  /// protégée par la RLS et le flux OAuth. Elle ne donne aucun accès aux tables
  /// `dtnh_*` (RLS activée sans policy).
  static const String supabaseAnonKey = String.fromEnvironment(
    'DTNH_SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zanNjenZzbnlrbmtkd2JjaWFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyNjk2NTIsImV4cCI6MjEwNTg0NTY1Mn0.Q5AWFbxx2RwxWcCZSYhuCr2h_rSdU-5oO9g-sCTHTrE',
  );

  /// Client ID OAuth Google (Google Cloud Console, type « application Web »).
  /// Vide = bouton Google désactivé avec un message explicite dans l'UI.
  static const String googleClientId = String.fromEnvironment(
    'DTNH_GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  /// Schéma profond utilisé par l'APK Android pour revenir dans l'application
  /// après le consentement Google (doit être déclaré dans le manifeste).
  static const String androidAuthCallbackScheme = 'mg.dtnh.dtnh_assistant_club';

  /// `true` si la connexion Google peut être proposée à l'utilisateur.
  ///
  /// Seule la clé Supabase est requise côté application : le client ID / secret
  /// Google sont configurés **côté Supabase** (Authentication > Providers), pas
  /// dans le bundle. `DTNH_GOOGLE_CLIENT_ID` ne sert qu'à documenter / vérifier
  /// la cohérence du projet Google Cloud en CI.
  static bool get isGoogleAuthConfigured => supabaseAnonKey.trim().isNotEmpty;
}
