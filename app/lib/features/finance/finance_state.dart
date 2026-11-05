import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_x.dart';
import '../../di/providers.dart';
import '../../domain/entities/finance_summary.dart';
import '../../domain/entities/financial_transaction.dart';
import '../../domain/enums/transaction_enums.dart';

/// Filtre appliqué à la liste des mouvements.
class FinanceFilter {
  const FinanceFilter({
    this.flow,
    this.category,
    this.month,
    this.search = '',
  });

  final TransactionFlow? flow;
  final TransactionCategory? category;

  /// `yyyy-MM` (null = tous les mois).
  final String? month;
  final String search;

  bool get isActive =>
      flow != null ||
      category != null ||
      month != null ||
      search.trim().isNotEmpty;

  FinanceFilter copyWith({
    TransactionFlow? flow,
    bool clearFlow = false,
    TransactionCategory? category,
    bool clearCategory = false,
    String? month,
    bool clearMonth = false,
    String? search,
  }) {
    return FinanceFilter(
      flow: clearFlow ? null : (flow ?? this.flow),
      category: clearCategory ? null : (category ?? this.category),
      month: clearMonth ? null : (month ?? this.month),
      search: search ?? this.search,
    );
  }
}

final financeFilterProvider =
    StateProvider<FinanceFilter>((ref) => const FinanceFilter());

/// Toutes les transactions (stream local, sans réseau).
final allTransactionsProvider = Provider<List<FinancialTransaction>>(
  (ref) => ref.watch(transactionsProvider).valueOrNull ??
      const <FinancialTransaction>[],
);

/// Solde global (toutes périodes).
final totalSummaryProvider = Provider<FinanceSummary>(
  (ref) => FinanceSummary.from(ref.watch(allTransactionsProvider)),
);

/// Synthèse du mois courant.
final currentMonthSummaryProvider = Provider<FinanceSummary>((ref) {
  final now = DateTime.now();
  final key = now.ym;
  final items = ref
      .watch(allTransactionsProvider)
      .where((tx) => tx.date.ym == key)
      .toList();
  return FinanceSummary.from(items);
});

/// Synthèse du mois précédent (pour la variation affichée sur le dashboard).
final previousMonthSummaryProvider = Provider<FinanceSummary>((ref) {
  final now = DateTime.now();
  final previous = DateTime(now.year, now.month - 1);
  final key = previous.ym;
  final items = ref
      .watch(allTransactionsProvider)
      .where((tx) => tx.date.ym == key)
      .toList();
  return FinanceSummary.from(items);
});

/// Série des 6 derniers mois pour le mini-graphique (ordre chronologique).
final monthlySeriesProvider = Provider<List<MonthlyFlow>>((ref) {
  final items = ref.watch(allTransactionsProvider);
  final now = DateTime.now();
  final months = <MonthlyFlow>[];
  for (var i = 5; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i);
    final key = month.ym;
    var income = 0;
    var expense = 0;
    for (final tx in items) {
      if (tx.date.ym != key) continue;
      if (tx.isIncome) {
        income += tx.amount;
      } else {
        expense += tx.amount;
      }
    }
    months.add(MonthlyFlow(month: month, income: income, expense: expense));
  }
  return months;
});

/// Transactions filtrées, triées du plus récent au plus ancien.
final filteredTransactionsProvider = Provider<List<FinancialTransaction>>(
  (ref) {
    final filter = ref.watch(financeFilterProvider);
    final items = ref.watch(allTransactionsProvider);
    final query = filter.search.trim().toLowerCase();

    return items.where((tx) {
      if (filter.flow != null && tx.flow != filter.flow) return false;
      if (filter.category != null && tx.category != filter.category) {
        return false;
      }
      if (filter.month != null && tx.date.ym != filter.month) return false;
      if (query.isNotEmpty) {
        final haystack = [
          tx.category.label,
          tx.details ?? '',
          tx.playerName ?? '',
          tx.staffName ?? '',
          tx.eventName ?? '',
          tx.authorName,
          tx.amount.toString(),
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        return b.createdAt.compareTo(a.createdAt);
      });
  },
);

final filteredSummaryProvider = Provider<FinanceSummary>(
  (ref) => FinanceSummary.from(ref.watch(filteredTransactionsProvider)),
);

/// Répartition des entrées (ou sorties) par motif, pour les barres du dashboard.
final categoryBreakdownProvider =
    Provider.family<List<MapEntry<TransactionCategory, int>>, TransactionFlow>(
  (ref, flow) {
    final summary = ref.watch(totalSummaryProvider);
    final map =
        flow == TransactionFlow.income ? summary.incomeByCategory : summary.expenseByCategory;
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  },
);
