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
}
