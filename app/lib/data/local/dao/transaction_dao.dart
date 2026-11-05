import '../../../core/utils/date_x.dart';
import '../../../domain/entities/financial_transaction.dart';
import '../local_database.dart';

/// Accès bas niveau aux transactions (box Hive `financial_transactions_v1`).
class TransactionDao {
  TransactionDao(this._db);

  final LocalDatabase _db;

  List<FinancialTransaction> getAll() {
    final items = _db.transactionBox.values.toList();
    items.sort(_byMostRecentFirst);
    return items;
  }

  FinancialTransaction? byId(String id) => _db.transactionBox.get(id);

  List<FinancialTransaction> byMonth(String ym) =>
      getAll().where((t) => t.date.ym == ym).toList();

  List<FinancialTransaction> between(DateTime from, DateTime to) => getAll()
      .where((t) => !t.date.isBefore(from) && !t.date.isAfter(to))
      .toList();

  Future<void> put(FinancialTransaction transaction) async {
    await _db.transactionBox.put(transaction.id, transaction);
    _db.notify(DbStore.transactions);
  }

  Future<void> deleteById(String id) async {
    await _db.transactionBox.delete(id);
    _db.notify(DbStore.transactions);
  }

  /// Applique une mise à jour de l'état de synchronisation sans repasser par
  /// la couche repository (utilisé par le moteur de sync).
  Future<void> patchSyncState(String id, FinancialTransaction updated) async {
    await _db.transactionBox.put(updated.id, updated);
    _db.notify(DbStore.transactions);
  }

  Stream<List<FinancialTransaction>> watchAll() async* {
    yield getAll();
    await for (final store in _db.changes) {
      if (store == DbStore.transactions) yield getAll();
    }
  }

  static int _byMostRecentFirst(
    FinancialTransaction a,
    FinancialTransaction b,
  ) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    return b.createdAt.compareTo(a.createdAt);
  }
}
