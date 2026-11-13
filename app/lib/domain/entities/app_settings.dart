import '../../core/config/app_config.dart';
import '../enums/sync_target.dart';

/// Configuration applicative persistée localement (box Hive `settings`).
///
/// Volontairement immutable : les écrans lisent un `AppSettings` via Riverpod
/// et déclenchent une écriture pour le modifier.
///
/// Deux cibles de synchronisation coexistent :
/// - **Supabase** (Edge Function `dtnh-sync` → PostgreSQL), valeur par défaut ;
/// - **Google Sheets** (webhook Apps Script), conservé pour les clubs qui ont
///   déjà déployé le script.
///
/// Les champs `supabaseUrl` / `supabaseSecret` sont vides par défaut : on
/// retombe alors sur les valeurs compilées dans [AppConfig], ce qui évite toute
/// saisie manuelle sur les téléphones du staff. Un champ renseigné dans les
/// réglages a toujours la priorité (utile pour un autre projet Supabase).
class AppSettings {
  const AppSettings({
    this.syncTarget = SyncTarget.supabase,
    this.supabaseUrl = '',
    this.supabaseSecret = '',
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

  /// Destination active des envois.
  final SyncTarget syncTarget;

  /// URL de l'Edge Function Supabase (vide = valeur de [AppConfig]).
  final String supabaseUrl;

  /// Secret partagé de l'Edge Function (vide = valeur de [AppConfig]).
  final String supabaseSecret;

  /// URL `/exec` du déploiement Google Apps Script (webhook).
  final String webhookUrl;

  /// Secret partagé envoyé dans chaque requête (validé côté Apps Script).
  final String webhookSecret;

  /// Identifiant anonyme de l'appareil : traçabilité dans le journal du serveur.
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

  /// Endpoint réellement utilisé (surcharge locale > valeur compilée).
  String get activeSyncUrl {
    if (syncTarget == SyncTarget.appsScript) return webhookUrl.trim();
    final custom = supabaseUrl.trim();
    return custom.isEmpty ? AppConfig.supabaseSyncUrl : custom;
  }

  /// Secret réellement utilisé (surcharge locale > valeur compilée).
  String get activeSyncSecret {
    if (syncTarget == SyncTarget.appsScript) return webhookSecret.trim();
    final custom = supabaseSecret.trim();
    return custom.isEmpty ? AppConfig.supabaseSyncSecret : custom;
  }

  /// URL configurée pour la cible active.
  bool get hasWebhook => activeSyncUrl.trim().isNotEmpty;

  /// Cible active complète (URL + secret).
  bool get hasSyncTarget =>
      activeSyncUrl.trim().isNotEmpty && activeSyncSecret.trim().isNotEmpty;

  /// Libellé de la cible, utilisé dans les messages d'erreur et l'UI.
  String get syncTargetLabel => syncTarget.label;

  bool get isConfigured => hasSyncTarget && hasAuthor;

  bool get hasAuthor =>
      (authorName?.trim().isNotEmpty ?? false) &&
      (authorId?.trim().isNotEmpty ?? false);

  AppSettings copyWith({
    SyncTarget? syncTarget,
    String? supabaseUrl,
    String? supabaseSecret,
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
      syncTarget: syncTarget ?? this.syncTarget,
      supabaseUrl: supabaseUrl ?? this.supabaseUrl,
      supabaseSecret: supabaseSecret ?? this.supabaseSecret,
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
