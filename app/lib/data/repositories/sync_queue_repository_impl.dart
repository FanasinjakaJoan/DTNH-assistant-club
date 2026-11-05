import 'package:uuid/uuid.dart';

import '../../domain/entities/sync_queue_item.dart';
import '../../domain/enums/sync_enums.dart';
import '../../domain/repositories/sync_queue_repository.dart';
import '../local/dao/sync_queue_dao.dart';

/// Implémentation de l'outbox sur Hive.
///
/// Règle de coalescence : une seule opération PENDING par entité. Si le staff
/// corrige un pointage deux fois hors-ligne, un seul envoi partira, avec le
/// dernier état — c'est exactement la sémantique « upsert » du Sheet.
class SyncQueueRepositoryImpl implements SyncQueueRepository {
  SyncQueueRepositoryImpl({
    required SyncQueueDao dao,
    Uuid uuid = const Uuid(),
  })  : _dao = dao,
        _uuid = uuid;

  final SyncQueueDao _dao;
  final Uuid _uuid;

  @override
  Future<SyncQueueItem> enqueue({
    required SyncEntityType entityType,
    required String entityId,
    required Map<String, dynamic> payload,
    SyncOperation operation = SyncOperation.upsert,
  }) async {
    final now = DateTime.now();
    final existing = _dao.findPendingFor(
      entityType: entityType,
      entityId: entityId,
    );

    final item = existing == null
        ? SyncQueueItem(
            id: _uuid.v4(),
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            payload: payload,
            createdAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            operation: operation,
            payload: payload,
            status: SyncState.pending,
            clearLastError: true,
            updatedAt: now,
          );

    await _dao.put(item);
    await _dao.applyPendingState(
      entityType: entityType,
      entityId: entityId,
    );
    return item;
  }

  @override
  Future<List<SyncQueueItem>> pendingBatch({
    required int limit,
    int maxAttempts = 8,
  }) =>
      Future<List<SyncQueueItem>>.value(
        _dao.pendingBatch(limit: limit, maxAttempts: maxAttempts),
      );

  @override
  Stream<List<SyncQueueItem>> watchAll() => _dao.watchAll();

  @override
  Future<SyncQueueCounters> counters() async => SyncQueueCounters(
        pending: _dao.count(SyncState.pending),
        error: _dao.count(SyncState.error),
        synced: _dao.count(SyncState.synced),
      );

  @override
  Future<SyncQueueItem?> findById(String itemId) async => _dao.byId(itemId);

  @override
  Future<void> markSynced({
    required List<String> itemIds,
    required String batchId,
  }) =>
      _dao.markSynced(ids: itemIds, batchId: batchId);

  @override
  Future<void> markError({
    required String itemId,
    required String error,
    String? batchId,
  }) =>
      _dao.markError(itemId: itemId, error: error, batchId: batchId);

  @override
  Future<void> resetForRetry(String itemId) => _dao.resetForRetry(itemId);

  @override
  Future<void> clearSynced() => _dao.clearSynced();

  @override
  Future<void> applySyncedState({
    required SyncEntityType entityType,
    required List<String> entityIds,
    required DateTime syncedAt,
  }) =>
      _dao.applySyncedState(
        entityType: entityType,
        entityIds: entityIds,
        syncedAt: syncedAt,
      );

  @override
  Future<void> applyErrorState({
    required SyncEntityType entityType,
    required List<String> entityIds,
  }) =>
      _dao.applyErrorState(entityType: entityType, entityIds: entityIds);

  @override
  Future<void> applyPendingState({
    required SyncEntityType entityType,
    required String entityId,
  }) =>
      _dao.applyPendingState(entityType: entityType, entityId: entityId);
}
