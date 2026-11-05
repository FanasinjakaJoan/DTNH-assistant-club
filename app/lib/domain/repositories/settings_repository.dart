import '../entities/app_settings.dart';

/// Contrat de configuration locale (webhook, auteur, préférences).
abstract interface class SettingsRepository {
  AppSettings get current;

  Stream<AppSettings> watch();

  Future<void> save(AppSettings settings);

  Future<void> updateAuthor({required String id, required String name});

  Future<void> updateWebhook({required String url, required String secret});

  /// Mémorise le succès du dernier envoi (affiché dans l'écran Synchro).
  Future<void> recordSyncSuccess(DateTime at);

  /// Mémorise le dernier message d'erreur (`null` pour l'effacer).
  Future<void> recordSyncFailure(String? error);
}
