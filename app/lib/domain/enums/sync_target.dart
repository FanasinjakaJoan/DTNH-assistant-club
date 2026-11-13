/// Destination des données synchronisées.
///
/// Les deux cibles partagent le **même contrat HTTP** (`push` / `ping` + lots
/// d'items nommés) : le moteur de synchronisation, la file d'attente et l'UI
/// sont identiques. Seul l'endpoint change, ce qui permet de basculer d'une
/// cible à l'autre sans migration de données locales.
enum SyncTarget {
  /// Edge Function Supabase (`dtnh-sync`) → PostgreSQL.
  supabase(
    code: 'SUPABASE',
    label: 'Supabase',
    description: 'Base PostgreSQL du club (recommandé)',
  ),

  /// Webhook Google Apps Script → Google Sheets.
  appsScript(
    code: 'APPS_SCRIPT',
    label: 'Google Sheets',
    description: 'Webhook Apps Script existant (/exec)',
  );

  const SyncTarget({
    required this.code,
    required this.label,
    required this.description,
  });

  /// Valeur stable persistée dans Hive.
  final String code;

  final String label;
  final String description;

  static SyncTarget fromCode(String? code) {
    switch (code?.toUpperCase()) {
      case 'APPS_SCRIPT':
      case 'APPSSCRIPT':
      case 'SHEETS':
        return SyncTarget.appsScript;
      default:
        return SyncTarget.supabase;
    }
  }
}
