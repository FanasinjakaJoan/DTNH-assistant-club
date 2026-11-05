import '../entities/financial_transaction.dart';

/// Contrat d'accès aux transactions financières.
abstract interface class TransactionRepository {
  Stream<List<FinancialTransaction>> watchAll();

  Future<List<FinancialTransaction>> all();

  Future<FinancialTransaction?> findById(String id);

  /// Insère ou met à jour une transaction et l'ajoute à la file de sync.
  Future<void> save(FinancialTransaction transaction);

  /// Suppression logique côté Sheet (opération `delete` dans la file).
  Future<void> delete(String id);
}
