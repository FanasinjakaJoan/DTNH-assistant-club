import 'package:uuid/uuid.dart';

import '../core/errors/app_exception.dart';
import '../data/remote/apps_script_client.dart';
import '../domain/enums/sync_enums.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/sync_queue_repository.dart';

/// Compte-rendu d'un passage de synchronisation (affiché dans l'UI et les logs).
class SyncReport {
  const SyncReport({
    required this.attempted,
    required this.succeeded,
    required this.failed,
    required this.completedAt,
    this.message,
    this.error,
    this.remaining = 0,
  });

  final int attempted;
  final int succeeded;
  final int failed;
  final DateTime completedAt;
  final String? message;
  final String? error;

  /// Nombre d'items encore en attente après ce lot.
  final int remaining;

  bool get isSuccess => error == null && failed == 0;

  bool get isEmpty => attempted == 0;

  static SyncReport idle() => SyncReport(
        attempted: 0,
        succeeded: 0,
        failed: 0,
        completedAt: DateTime.now(),
        message: 'Rien à synchroniser',
      );

  @override
  String toString() =>
      'SyncReport(attempted: $attempted, ok: $succeeded, ko: $failed, '
      'remaining: $remaining, error: $error)';
}

/// Moteur de synchronisation : **outbox + upsert idempotent**.
///
/// Déroulé d'un passage :
/// 1. lit la configuration (cible active, URL, secret) ;
/// 2. récupère les N items non synchronisés (PENDING / ERROR < maxAttempts) ;
/// 3. construit un lot hétérogène (présences + transactions + joueurs) ;
/// 4. POST unique vers la **cible active** (Edge Function Supabase ou Apps
///    Script — même contrat JSON) ;
/// 5. marque chaque item `SYNCED` ou `ERROR` selon la réponse **par item** ;
/// 6. propage l'état aux entités (icône dans les listes) et met à jour
///    `lastSyncAt`.
///
/// Aucune exception de transport ne remonte sans avoir d'abord incrémenté le
/// compteur de tentatives : rien ne peut être perdu silencieusement.
class SyncEngine {
  SyncEngine({
    required SyncQueueRepository queue,
    required AppsScriptClient client,
    required SettingsRepository settings,
    Uuid uuid = const Uuid(),
  })  : _queue = queue,
        _client = client,
        _settings = settings,
        _uuid = uuid;

  final SyncQueueRepository _queue;
  final AppsScriptClient _client;
  final SettingsRepository _settings;

  /// Dernier essai de récupération de configuration (anti-rebond).
  DateTime? _lastRecoveryAt;

  /// Le serveur a répondu, mais le club n'utilise pas Google Sheets.
  ///
  /// Permet d'afficher « ce club synchronise vers Supabase, changez de cible »
  /// plutôt qu'un « non configuré » trompeur, qui laisserait croire à une
  /// panne alors que la configuration est simplement absente par choix.
  bool _clubHasNoSheets = false;
  final Uuid _uuid;

  /// Nombre maximum de tentatives avant passage en `ERROR` définitif
  /// (l'item reste réessayable manuellement depuis l'écran Synchro).
  static const int maxAttempts = 8;

  /// Taille d'un lot : compromise entre latence serveur (~1-3 s) et
  /// taille de payload (un pointage de 15 joueurs => 15 items).
  static const int defaultBatchSize = 80;

  Future<SyncReport> pushPending({int batchSize = defaultBatchSize}) async {
    final settings = _settings.current;
    final target = settings.syncTargetLabel;

    if (!settings.hasSyncTarget) {
      // Dernier recours avant d'échouer : si une session Google existe, on
      // (re)demande la configuration du club — c'est exactement le scénario
      // que l'utilisateur décrit (« il suffit de se connecter »). Une URL
      // peut arriver sans que l'appel au démarrage ait abouti (hors-ligne à
      // ce moment-là, session rétablie depuis...).
      final recovered = await _recoverConfiguration();
      if (recovered) {
        return pushPending(batchSize: batchSize);
      }
      throw SyncConfigurationException(
        _clubHasNoSheets
            ? 'Ce club ne synchronise pas vers Google Sheets (cible '
                '« $target » sans URL). Choisissez la cible « Supabase » dans '
                'Réglages > Synchronisation — elle fonctionne sans saisie.'
            : 'Synchronisation non configurée : aucune URL pour la cible '
                '« $target ». Connectez-vous avec Google (la configuration '
                'du club est alors récupérée automatiquement) ou renseignez '
                'l\'URL dans Réglages > Synchronisation.',
      );
    }

    final items = await _queue.pendingBatch(
      limit: batchSize,
      maxAttempts: maxAttempts,
    );

    if (items.isEmpty) {
      await _settings.recordSyncSuccess(DateTime.now());
      return SyncReport.idle();
    }

    final batchId = _uuid.v4();
    final entries =
        items.map((item) => SheetBatchEntry(item: item)).toList(growable: false);

    SheetBatchResponse response;
    try {
      response = await _client.sendBatch(
        webhookUrl: settings.activeSyncUrl,
        secret: settings.activeSyncSecret,
        deviceId: settings.deviceId,
        batchId: batchId,
        entries: entries,
      );
    } on AppException catch (error) {
      // Échec global : on incrémente les tentatives pour déclencher le backoff.
      final failedByType = <SyncEntityType, List<String>>{};
      for (final item in items) {
        await _queue.markError(
          itemId: item.id,
          error: error.message,
          batchId: batchId,
        );
        failedByType.putIfAbsent(item.entityType, () => <String>[]).add(item.entityId);
      }
      for (final entry in failedByType.entries) {
        await _queue.applyErrorState(
          entityType: entry.key,
          entityIds: entry.value,
        );
      }
      await _settings.recordSyncFailure(error.message);
      final remaining = (await _queue.counters()).outstanding;
      return SyncReport(
        attempted: items.length,
        succeeded: 0,
        failed: items.length,
        completedAt: DateTime.now(),
        error: error.message,
        remaining: remaining,
      );
    }

    // Succès partiel : on traite item par item.
    final okIds = <String>[];
    final okEntities = <SyncEntityType, List<String>>{};
    final koEntities = <SyncEntityType, List<String>>{};
    final errorMessages = <String>[];

    for (final item in items) {
      final result = response.resultFor(item.id);
      // Un serveur qui répond `ok: true` sans détail (ou sans détail pour cet
      // item) est considéré comme ayant traité le lot : c'est le comportement
      // de repli lorsque le serveur ne renvoie pas de résultat par ligne.
      final treated = result?.ok ?? response.ok;
      if (treated) {
        okIds.add(item.id);
        okEntities.putIfAbsent(item.entityType, () => <String>[]).add(item.entityId);
      } else {
        final message = result?.error ?? 'Ligne refusée par le serveur';
        errorMessages.add(message);
        await _queue.markError(
          itemId: item.id,
          error: message,
          batchId: batchId,
        );
        koEntities.putIfAbsent(item.entityType, () => <String>[]).add(item.entityId);
      }
    }

    final syncedAt = response.serverTime ?? DateTime.now();
    if (okIds.isNotEmpty) {
      await _queue.markSynced(itemIds: okIds, batchId: batchId);
      for (final entry in okEntities.entries) {
        await _queue.applySyncedState(
          entityType: entry.key,
          entityIds: entry.value,
          syncedAt: syncedAt,
        );
      }
    }
    for (final entry in koEntities.entries) {
      await _queue.applyErrorState(
        entityType: entry.key,
        entityIds: entry.value,
      );
    }

    final remaining = (await _queue.counters()).outstanding;

    if (okIds.isEmpty && items.isNotEmpty) {
      final message = errorMessages.isEmpty
          ? 'Toutes les lignes ont été refusées par le serveur.'
          : errorMessages.first;
      await _settings.recordSyncFailure(message);
      return SyncReport(
        attempted: items.length,
        succeeded: 0,
        failed: items.length,
        completedAt: DateTime.now(),
        error: message,
        remaining: remaining,
      );
    }

    await _settings.recordSyncSuccess(syncedAt);
    return SyncReport(
      attempted: items.length,
      succeeded: okIds.length,
      failed: items.length - okIds.length,
      completedAt: DateTime.now(),
      message: remaining > 0
          ? '${okIds.length} élément(s) synchronisé(s) vers $target, '
              '$remaining restant(s)'
          : '${okIds.length} élément(s) synchronisé(s) vers $target',
      remaining: remaining,
    );
  }

  /// Vide la file en enchaînant les lots (bouton « Synchroniser maintenant »).
  Future<SyncReport> drain({int maxBatches = 10}) async {
    var attempted = 0;
    var succeeded = 0;
    var failed = 0;
    var remaining = 0;
    String? lastMessage;
    String? lastError;
    DateTime? completedAt;

    for (var batch = 0; batch < maxBatches; batch++) {
      final report = await pushPending();
      attempted += report.attempted;
      succeeded += report.succeeded;
      failed += report.failed;
      remaining = report.remaining;
      lastMessage = report.message ?? lastMessage;
      lastError = report.error ?? lastError;
      completedAt = report.completedAt;
      if (report.attempted == 0) break;
      if (report.succeeded == 0) break; // tout échoue : inutile d'insister
    }

    return SyncReport(
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      completedAt: completedAt ?? DateTime.now(),
      message: lastMessage,
      error: lastError,
      remaining: remaining,
    );
  }

  /// Tente de récupérer la configuration du club, une seule fois par passage.
  ///
  /// Renvoie `true` si une URL de synchronisation est disponible après
  /// l'appel. Volontairement silencieux : c'est un chemin de secours, l'appel
  /// nominal se fait au démarrage / à la connexion.
  Future<bool> _recoverConfiguration() async {
    // Anti-rebond : une panne réseau ne doit pas provoquer un appel de
    // configuration à chaque item en échec. 60 s suffisent à absorber le cas
    // d'une reprise en rafale sans bloquer une nouvelle tentative utile.
    final now = DateTime.now();
    if (_lastRecoveryAt != null &&
        now.difference(_lastRecoveryAt!) < const Duration(seconds: 60)) {
      return false;
    }
    _lastRecoveryAt = now;
    try {
      final client = _client;
      if (!await client.hasSession()) return false;
      final settings = _settings.current;
      final endpoint = settings.configEndpoint;
      if (endpoint.trim().isEmpty) return false;
      final club = await client.fetchClubConfig(
        webhookUrl: endpoint,
        secret: settings.configSecret,
      );
      _clubHasNoSheets = !club.hasSheets;
      if (!club.hasSheets) return false;
      await _settings.saveClubConfig(
        webhookUrl: club.webhookUrl ?? '',
        webhookSecret: club.webhookSecret ?? '',
        sheetId: club.sheetId,
      );
      return _settings.current.hasSyncTarget;
    } catch (_) {
      // Échec silencieux : l'appelant produit déjà un message explicite.
      return false;
    }
  }

  Future<String> testConnection() => _client.ping(
        webhookUrl: _settings.current.activeSyncUrl,
        secret: _settings.current.activeSyncSecret,
      );

  /// `true` s'il reste au moins un élément à envoyer (PENDING ou ERROR).
  ///
  /// Permet au planificateur de ne pas déclencher un passage inutile : sans ce
  /// filtre, le filet de sécurité périodique mettrait à jour `lastSyncAt` même
  /// quand rien n'a été envoyé, ce qui rendrait cet indicateur trompeur.
  Future<bool> hasOutstanding() async =>
      (await _queue.counters()).outstanding > 0;
}
