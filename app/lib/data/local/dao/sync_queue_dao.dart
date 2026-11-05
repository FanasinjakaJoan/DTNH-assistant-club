import '../../../domain/entities/attendance_entry.dart';
import '../../../domain/entities/financial_transaction.dart';
import '../../../domain/entities/player.dart';
import '../../../domain/entities/sync_queue_item.dart';
import '../../../domain/enums/sync_enums.dart';
import '../local_database.dart';

/// Accès bas niveau à la file d'attente de synchronisation.
class SyncQueueDao {
  SyncQueueDao(this._db);

  final LocalDatabase _db;

  List<SyncQueueItem> getAll() {
    final items = _db.syncQueueBox.values.toList();
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  SyncQueueItem? byId(String id) => _db.syncQueueBox.get(id);

  /// Item encore PENDING pour une entité : sert à **coalescer** les écritures
  /// successives (pointer deux fois la même séance ne crée pas deux envois).
  SyncQueueItem? findPendingFor({
    required SyncEntityType entityType,
    required String entityId,
  }) {
    for (final item in _db.syncQueueBox.values) {
      if (item.entityType == entityType &&
          item.entityId == entityId &&
          item.isPending) {
        return item;
      }
    }
    return null;
  }

  List<SyncQueueItem> pendingBatch({
    required int limit,
    int maxAttempts = 8,
  }) {
    final items = _db.syncQueueBox.values
        .where((item) =>
            item.status != SyncState.synced && item.attempts < maxAttempts)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items.take(limit).toList();
  }

  int count(SyncState status) =>
      _db.syncQueueBox.values.where((item) => item.status == status).length;

  int countOutstanding() => _db.syncQueueBox.values
      .where((item) => item.status != SyncState.synced)
      .length;

  Future<void> put(SyncQueueItem item) async {
    await _db.syncQueueBox.put(item.id, item);
    _db.notify(DbStore.syncQueue);
  }

  Future<void> putAll(List<SyncQueueItem> items) async {
    if (items.isEmpty) return;
    await _db.syncQueueBox.putAll({for (final i in items) i.id: i});
    _db.notify(DbStore.syncQueue);
  }

  Future<void> markSynced({
    required Iterable<String> ids,
    required String batchId,
  }) async {
    final now = DateTime.now();
    final updates = <String, SyncQueueItem>{};
    for (final id in ids) {
      final item = _db.syncQueueBox.get(id);
      if (item == null) continue;
      updates[id] = item.copyWith(
        status: SyncState.synced,
        attempts: item.attempts + 1,
        clearLastError: true,
        syncedAt: now,
        updatedAt: now,
        batchId: batchId,
      );
    }
    await putAll(updates.values.toList());
  }

  Future<void> markError({
    required String itemId,
    required String error,
    String? batchId,
  }) async {
    final item = _db.syncQueueBox.get(itemId);
    if (item == null) return;
    final now = DateTime.now();
    await put(
      item.copyWith(
        status: SyncState.error,
        attempts: item.attempts + 1,
        lastError: _truncate(error),
        updatedAt: now,
        batchId: batchId,
      ),
    );
  }

  Future<void> resetForRetry(String itemId) async {
    final item = _db.syncQueueBox.get(itemId);
    if (item == null || item.status == SyncState.synced) return;
    await put(
      item.copyWith(
        status: SyncState.pending,
        attempts: 0,
        clearLastError: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> clearSynced() async {
    final syncedIds = _db.syncQueueBox.values
        .where((item) => item.status == SyncState.synced)
        .map((item) => item.id)
        .toList();
    if (syncedIds.isEmpty) return;
    await _db.syncQueueBox.deleteAll(syncedIds);
    _db.notify(DbStore.syncQueue);
  }

  Stream<List<SyncQueueItem>> watchAll() async* {
    yield getAll();
    await for (final store in _db.changes) {
      if (store == DbStore.syncQueue) yield getAll();
    }
  }

  /// Propage l'état « synchronisé » aux entités métier (dénormalisation UI).
  Future<void> applySyncedState({
    required SyncEntityType entityType,
    required Iterable<String> entityIds,
    required DateTime syncedAt,
  }) async {
    final ids = entityIds.toSet();
    if (ids.isEmpty) return;

    if (entityType == SyncEntityType.attendance) {
      final updates = <String, AttendanceEntry>{};
      for (final entry in _db.attendanceBox.values) {
        if (ids.contains(entry.id)) {
          updates[entry.id] = entry.copyWith(
            syncState: SyncState.synced,
            syncedAt: syncedAt,
          );
        }
      }
      if (updates.isNotEmpty) {
        await _db.attendanceBox.putAll(updates);
        _db.notify(DbStore.attendance);
      }
      return;
    }

    if (entityType == SyncEntityType.transaction) {
      final updates = <String, FinancialTransaction>{};
      for (final tx in _db.transactionBox.values) {
        if (ids.contains(tx.id)) {
          updates[tx.id] = tx.copyWith(
            syncState: SyncState.synced,
            syncedAt: syncedAt,
          );
        }
      }
      if (updates.isNotEmpty) {
        await _db.transactionBox.putAll(updates);
        _db.notify(DbStore.transactions);
      }
      return;
    }

    final playerUpdates = <String, Player>{};
    for (final player in _db.playerBox.values) {
      if (ids.contains(player.id)) {
        playerUpdates[player.id] = player.copyWith(
          syncState: SyncState.synced,
          syncedAt: syncedAt,
        );
      }
    }
    if (playerUpdates.isNotEmpty) {
      await _db.playerBox.putAll(playerUpdates);
      _db.notify(DbStore.players);
    }
  }

  Future<void> applyErrorState({
    required SyncEntityType entityType,
    required Iterable<String> entityIds,
  }) async {
    final ids = entityIds.toSet();
    if (ids.isEmpty) return;

    if (entityType == SyncEntityType.attendance) {
      final updates = <String, AttendanceEntry>{};
      for (final entry in _db.attendanceBox.values) {
        if (ids.contains(entry.id)) {
          updates[entry.id] = entry.copyWith(syncState: SyncState.error);
        }
      }
      if (updates.isNotEmpty) {
        await _db.attendanceBox.putAll(updates);
        _db.notify(DbStore.attendance);
      }
      return;
    }

    if (entityType == SyncEntityType.transaction) {
      final updates = <String, FinancialTransaction>{};
      for (final tx in _db.transactionBox.values) {
        if (ids.contains(tx.id)) {
          updates[tx.id] = tx.copyWith(syncState: SyncState.error);
        }
      }
      if (updates.isNotEmpty) {
        await _db.transactionBox.putAll(updates);
        _db.notify(DbStore.transactions);
      }
      return;
    }

    final playerUpdates = <String, Player>{};
    for (final player in _db.playerBox.values) {
      if (ids.contains(player.id)) {
        playerUpdates[player.id] = player.copyWith(syncState: SyncState.error);
      }
    }
    if (playerUpdates.isNotEmpty) {
      await _db.playerBox.putAll(playerUpdates);
      _db.notify(DbStore.players);
    }
  }

  Future<void> applyPendingState({
    required SyncEntityType entityType,
    required String entityId,
  }) async {
    if (entityType == SyncEntityType.attendance) {
      final entry = _db.attendanceBox.get(entityId);
      if (entry == null) return;
      await _db.attendanceBox.put(
        entityId,
        entry.copyWith(syncState: SyncState.pending, clearSyncedAt: true),
      );
      _db.notify(DbStore.attendance);
      return;
    }

    if (entityType == SyncEntityType.transaction) {
      final tx = _db.transactionBox.get(entityId);
      if (tx == null) return;
      await _db.transactionBox.put(
        entityId,
        tx.copyWith(syncState: SyncState.pending, clearSyncedAt: true),
      );
      _db.notify(DbStore.transactions);
      return;
    }

    final player = _db.playerBox.get(entityId);
    if (player == null) return;
    await _db.playerBox.put(
      entityId,
      player.copyWith(syncState: SyncState.pending, clearSyncedAt: true),
    );
    _db.notify(DbStore.players);
  }

  String _truncate(String value) =>
      value.length <= 400 ? value : '${value.substring(0, 400)}…';
}
