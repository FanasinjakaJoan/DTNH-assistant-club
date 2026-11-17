import '../entities/app_settings.dart';
import '../enums/sync_target.dart';

/// Contrat de configuration locale (cible de sync, auteur, préférences).
abstract interface class SettingsRepository {
  AppSettings get current;

  Stream<AppSettings> watch();

  Future<void> save(AppSettings settings);

  Future<void> updateAuthor({required String id, required String name});

  /// Configure le webhook Google Apps Script (cible historique).
  Future<void> updateWebhook({required String url, required String secret});

  /// Configure l'Edge Function Supabase (cible par défaut).
  ///
  /// Une URL ou un secret vide est autorisé : [AppSettings.activeSyncUrl]
  /// retombe alors sur les valeurs compilées dans `AppConfig`.
  Future<void> updateSupabase({required String url, required String secret});

  /// Change la cible active sans toucher aux paramètres de l'autre cible.
  Future<void> updateSyncTarget(SyncTarget target);

  /// Enregistre la configuration du club reçue de l'Edge Function
  /// (action `config`) : URL du webhook Apps Script, secret, ID du Sheet.
  ///
  /// Une `webhookUrl` vide efface la configuration du club (le club n'utilise
  /// pas Google Sheets) ; la cible Supabase reste utilisable sans réglage.
  Future<void> saveClubConfig({
    required String webhookUrl,
    required String webhookSecret,
    String? sheetId,
    DateTime? syncedAt,
  });

  /// Oublie la configuration du club (déconnexion, changement de compte).
  Future<void> clearClubConfig();

  /// Mémorise le succès du dernier envoi (affiché dans l'écran Synchro).
  Future<void> recordSyncSuccess(DateTime at);

  /// Mémorise le dernier message d'erreur (`null` pour l'effacer).
  Future<void> recordSyncFailure(String? error);
}
