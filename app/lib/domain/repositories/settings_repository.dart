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

  /// Mémorise le succès du dernier envoi (affiché dans l'écran Synchro).
  Future<void> recordSyncSuccess(DateTime at);

  /// Mémorise le dernier message d'erreur (`null` pour l'effacer).
  Future<void> recordSyncFailure(String? error);
}
