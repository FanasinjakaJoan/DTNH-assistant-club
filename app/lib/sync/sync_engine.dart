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
      throw SyncConfigurationException(
        'Synchronisation non configurée : renseignez l\'URL et le secret de '
        'la cible « $target » dans Réglages > Synchronisation.',
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

  Future<String> testConnection() => _client.ping(
        webhookUrl: _settings.current.activeSyncUrl,
        secret: _settings.current.activeSyncSecret,
      );
}
