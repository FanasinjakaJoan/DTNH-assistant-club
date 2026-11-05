import '../../domain/entities/financial_transaction.dart';
import '../../domain/enums/sync_enums.dart';
import '../../domain/repositories/sync_queue_repository.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../local/dao/transaction_dao.dart';
import '../remote/sync_payloads.dart';

/// Implémentation locale des transactions financières.
class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl({
    required TransactionDao dao,
    required SyncQueueRepository queue,
  })  : _dao = dao,
        _queue = queue;

  final TransactionDao _dao;
  final SyncQueueRepository _queue;

  @override
  Stream<List<FinancialTransaction>> watchAll() => _dao.watchAll();

  @override
  Future<List<FinancialTransaction>> all() async => _dao.getAll();

  @override
  Future<FinancialTransaction?> findById(String id) async => _dao.byId(id);

  @override
  Future<void> save(FinancialTransaction transaction) async {
    final now = DateTime.now();
    final toStore = transaction.copyWith(
      syncState: SyncState.pending,
      clearSyncedAt: true,
      updatedAt: now,
    );
    await _dao.put(toStore);
    await _queue.enqueue(
      entityType: SyncEntityType.transaction,
      entityId: toStore.id,
      payload: SyncPayloads.transaction(toStore),
    );
  }

  @override
  Future<void> delete(String id) async {
    final existing = _dao.byId(id);
    if (existing == null) return;
    await _queue.enqueue(
      entityType: SyncEntityType.transaction,
      entityId: id,
      payload: SyncPayloads.tombstone(id),
      operation: SyncOperation.delete,
    );
    await _dao.deleteById(id);
  }
}
