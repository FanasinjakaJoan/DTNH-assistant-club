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
/// **Rien n'est à saisir par le staff.** La configuration de référence vit côté
/// serveur (secrets de l'Edge Function) et est distribuée aux membres connectés
/// par l'action `config` de `dtnh-sync`. Localement, trois niveaux se
/// succèdent :
///
/// 1. la valeur **récupérée du club** (`clubWebhookUrl`, `clubWebhookSecret`,
///    `clubSheetId`, horodatage `clubConfigSyncedAt`) ;
/// 2. la saisie **manuelle** éventuelle (surcharge d'un autre projet Supabase) ;
/// 3. les valeurs **compilées** dans [AppConfig] (repli hors-ligne).
///
/// Une cible est considérée comme configurée dès qu'une URL est disponible :
/// le JWT de session suffit à authentifier l'appel, le secret partagé n'est
/// qu'un second chemin. C'est ce qui permet à un utilisateur simplement
/// connecté avec Google de synchroniser sans jamais ouvrir les réglages.
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
    this.clubWebhookUrl,
    this.clubWebhookSecret,
    this.clubSheetId,
    this.clubConfigSyncedAt,
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

  /// URL `/exec` du webhook Apps Script **telle que publiée par le club**
  /// (action `config` de l'Edge Function). `null` = pas encore récupérée.
  final String? clubWebhookUrl;

  /// Secret du webhook Apps Script publié par le club. Distribué uniquement
  /// aux membres authentifiés, jamais présent dans un build public.
  final String? clubWebhookSecret;

  /// ID du Google Sheet publié par le club.
  final String? clubSheetId;

  /// Dernière récupération réussie de la configuration du club.
  final DateTime? clubConfigSyncedAt;

  /// `true` si une URL de webhook Apps Script a été reçue du club.
  bool get hasClubConfig =>
      (clubWebhookUrl?.trim().isNotEmpty ?? false);

  /// `true` si l'application a déjà pu interroger le serveur du club.
  ///
  /// Distinct de [hasClubConfig] : un club peut n'avoir aucune cible Sheets
  /// (tout Supabase). Dans ce cas la configuration est « à jour » même sans
  /// webhook — sinon l'appel `config` serait rejoué à chaque reprise.
  bool get isClubConfigFetched => clubConfigSyncedAt != null;

  /// Endpoint réellement utilisé.
  ///
  /// Priorité : saisie locale > configuration du club > valeur compilée. Une
  /// saisie locale reste prioritaire pour ne jamais casser un appareil déjà
  /// paramétré à la main (autre projet Supabase, webhook de test...).
  String get activeSyncUrl {
    if (syncTarget == SyncTarget.appsScript) {
      return _firstNonEmpty(<String?>[
        webhookUrl,
        clubWebhookUrl,
        AppConfig.sheetsWebhookUrl,
      ]);
    }
    return _firstNonEmpty(<String?>[
      supabaseUrl,
      AppConfig.supabaseSyncUrl,
    ]);
  }

  /// Secret réellement utilisé.
  ///
  /// Peut être vide : une session Google valide suffit à authentifier un envoi
  /// (c'est le chemin privilégié). Le secret n'est qu'un repli hors-ligne.
  String get activeSyncSecret {
    if (syncTarget == SyncTarget.appsScript) {
      return _firstNonEmpty(<String?>[
        webhookSecret,
        clubWebhookSecret,
        AppConfig.sheetsWebhookSecret,
      ]);
    }
    return _firstNonEmpty(<String?>[
      supabaseSecret,
      AppConfig.supabaseSyncSecret,
    ]);
  }

  /// Endpoint qui sert la configuration du club (action `config`).
  ///
  /// C'est **toujours** l'Edge Function Supabase, même quand la cible d'envoi
  /// est Apps Script : sinon un appareil neuf, qui n'a encore aucune URL de
  /// webhook, n'aurait rien à interroger — précisément le cas où l'on veut
  /// distribuer la configuration. Ne dépend donc pas de [syncTarget].
  String get configEndpoint {
    return _firstNonEmpty(<String?>[
      supabaseUrl,
      AppConfig.supabaseSyncUrl,
    ]);
  }

  /// Secret joint à la requête de configuration (repli hors-ligne uniquement).
  String get configSecret {
    return _firstNonEmpty(<String?>[
      supabaseSecret,
      AppConfig.supabaseSyncSecret,
    ]);
  }

  /// `true` si la cible active possède une URL exploitable.
  ///
  /// On ne conditionne plus la synchronisation à la présence d'un secret : un
  /// membre connecté avec Google s'authentifie par son JWT. Exiger un secret
  /// rendait l'application « non configurée » alors que la connexion Google
  /// suffisait — c'était le principal motif de synchronisation bloquée.
  bool get hasSyncTarget => activeSyncUrl.trim().isNotEmpty;

  /// Conservé pour compatibilité : `true` si une URL est définie.
  bool get hasWebhook => hasSyncTarget;

  /// Libellé de la cible, utilisé dans les messages d'erreur et l'UI.
  String get syncTargetLabel => syncTarget.label;

  /// `true` si la synchronisation peut réellement partir en un geste.
  bool get isConfigured => hasSyncTarget && hasAuthor;

  /// `true` si la cible peut être appelée sans secret (session Google).
  bool get isSecretMissing => activeSyncSecret.trim().isEmpty;

  /// ID du Sheet affiché : saisie locale > configuration du club > build.
  String? get activeSheetId => _firstNonEmptyOrNull(<String?>[
        sheetId,
        clubSheetId,
        AppConfig.sheetId,
      ]);

  /// `true` si cette compilation embarque la configuration Google/Supabase.
  static bool get supportsGoogleAuth => AppConfig.isGoogleAuthConfigured;

  static String _firstNonEmpty(List<String?> candidates) =>
      _firstNonEmptyOrNull(candidates) ?? '';

  static String? _firstNonEmptyOrNull(List<String?> candidates) {
    for (final candidate in candidates) {
      final value = candidate?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

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
    String? clubWebhookUrl,
    String? clubWebhookSecret,
    String? clubSheetId,
    DateTime? clubConfigSyncedAt,
    bool clearClubConfig = false,
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
      clubWebhookUrl:
          clearClubConfig ? null : (clubWebhookUrl ?? this.clubWebhookUrl),
      clubWebhookSecret: clearClubConfig
          ? null
          : (clubWebhookSecret ?? this.clubWebhookSecret),
      clubSheetId: clearClubConfig ? null : (clubSheetId ?? this.clubSheetId),
      clubConfigSyncedAt: clearClubConfig
          ? null
          : (clubConfigSyncedAt ?? this.clubConfigSyncedAt),
    );
  }
}
