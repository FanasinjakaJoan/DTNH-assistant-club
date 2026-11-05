/// Configuration applicative persistée localement (box Hive `settings`).
///
/// Volontairement immutable : les écrans lisent un `AppSettings` via Riverpod
/// et déclenchent une écriture pour le modifier.
class AppSettings {
  const AppSettings({
    this.webhookUrl = '',
    this.webhookSecret = '',
    this.deviceId = '',
    this.authorName,
    this.authorId,
    this.autoSyncEnabled = true,
    this.lastSyncAt,
    this.lastSyncError,
    this.sheetId,
  });

  /// URL `/exec` du déploiement Google Apps Script (webhook).
  final String webhookUrl;

  /// Secret partagé envoyé dans chaque requête (validé côté Apps Script).
  final String webhookSecret;

  /// Identifiant anonyme de l'appareil : traçabilité dans le journal du Sheet.
  final String deviceId;

  /// Auteur du pointage / de la saisie en cours.
  final String? authorName;
  final String? authorId;

  /// Synchronisation automatique au retour du réseau.
  final bool autoSyncEnabled;

  final DateTime? lastSyncAt;
  final String? lastSyncError;

  /// ID du Google Sheet (facultatif, informatif dans les réglages).
  final String? sheetId;

  bool get hasWebhook => webhookUrl.trim().isNotEmpty;

  bool get isConfigured =>
      hasWebhook && webhookSecret.trim().isNotEmpty && hasAuthor;

  bool get hasAuthor =>
      (authorName?.trim().isNotEmpty ?? false) &&
      (authorId?.trim().isNotEmpty ?? false);

  AppSettings copyWith({
    String? webhookUrl,
    String? webhookSecret,
    String? deviceId,
    String? authorName,
    String? authorId,
    bool? autoSyncEnabled,
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
    String? lastSyncError,
    bool clearLastSyncError = false,
    String? sheetId,
  }) {
    return AppSettings(
      webhookUrl: webhookUrl ?? this.webhookUrl,
      webhookSecret: webhookSecret ?? this.webhookSecret,
      deviceId: deviceId ?? this.deviceId,
      authorName: authorName ?? this.authorName,
      authorId: authorId ?? this.authorId,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
      lastSyncError:
          clearLastSyncError ? null : (lastSyncError ?? this.lastSyncError),
      sheetId: sheetId ?? this.sheetId,
    );
  }
}
