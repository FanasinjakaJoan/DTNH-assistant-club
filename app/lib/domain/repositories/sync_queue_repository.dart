import '../entities/sync_queue_item.dart';
import '../enums/sync_enums.dart';

/// Résultat agrégé de la file d'attente (compteurs pour l'écran Synchro).
class SyncQueueCounters {
  const SyncQueueCounters({
    this.pending = 0,
    this.error = 0,
    this.synced = 0,
  });

  final int pending;
  final int error;
  final int synced;

  int get outstanding => pending + error;

  bool get isEmpty => outstanding == 0 && synced == 0;

  SyncQueueCounters copyWith({int? pending, int? error, int? synced}) =>
      SyncQueueCounters(
        pending: pending ?? this.pending,
        error: error ?? this.error,
        synced: synced ?? this.synced,
      );
}

/// Contrat de la file d'attente de synchronisation (outbox).
abstract interface class SyncQueueRepository {
  /// Ajoute — ou fusionne avec l'item PENDING existant — une opération.
  Future<SyncQueueItem> enqueue({
    required SyncEntityType entityType,
    required String entityId,
    required Map<String, dynamic> payload,
    SyncOperation operation = SyncOperation.upsert,
  });

  Future<List<SyncQueueItem>> pendingBatch({
    required int limit,
    int maxAttempts = 8,
  });

  Stream<List<SyncQueueItem>> watchAll();

  Future<SyncQueueCounters> counters();

  Future<void> markSynced({
    required List<String> itemIds,
    required String batchId,
  });

  Future<void> markError({
    required String itemId,
    required String error,
    String? batchId,
  });

  Future<void> resetForRetry(String itemId);

  /// Vérifie qu'un item est encore PENDING avant de marquer l'entité comme
  /// synchronisée (évite les courses entre deux envois concurrents).
  Future<SyncQueueItem?> findById(String itemId);

  Future<void> clearSynced();

  /// Met à jour l'état de synchronisation des entités après un envoi réussi.
  Future<void> applySyncedState({
    required SyncEntityType entityType,
    required List<String> entityIds,
    required DateTime syncedAt,
  });

  Future<void> applyErrorState({
    required SyncEntityType entityType,
    required List<String> entityIds,
  });

  Future<void> applyPendingState({
    required SyncEntityType entityType,
    required String entityId,
  });
}
