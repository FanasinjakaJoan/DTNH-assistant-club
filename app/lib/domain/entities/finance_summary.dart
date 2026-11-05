import '../../core/utils/date_x.dart';
import '../enums/transaction_enums.dart';
import 'financial_transaction.dart';

/// Synthèse financière locale d'une période.
class FinanceSummary {
  const FinanceSummary({
    required this.income,
    required this.expense,
    required this.transactionCount,
    required this.incomeByCategory,
    required this.expenseByCategory,
    this.periodLabel = '',
  });

  final int income;
  final int expense;
  final int transactionCount;
  final Map<TransactionCategory, int> incomeByCategory;
  final Map<TransactionCategory, int> expenseByCategory;
  final String periodLabel;

  int get balance => income - expense;

  bool get isEmpty => transactionCount == 0;

  static const FinanceSummary empty = FinanceSummary(
    income: 0,
    expense: 0,
    transactionCount: 0,
    incomeByCategory: {},
    expenseByCategory: {},
  );

  /// Construit la synthèse à partir d'une liste de transactions.
  factory FinanceSummary.from(List<FinancialTransaction> transactions) {
    var income = 0;
    var expense = 0;
    final incomeByCategory = <TransactionCategory, int>{};
    final expenseByCategory = <TransactionCategory, int>{};

    for (final tx in transactions) {
      if (tx.isIncome) {
        income += tx.amount;
        incomeByCategory.update(
          tx.category,
          (value) => value + tx.amount,
          ifAbsent: () => tx.amount,
        );
      } else {
        expense += tx.amount;
        expenseByCategory.update(
          tx.category,
          (value) => value + tx.amount,
          ifAbsent: () => tx.amount,
        );
      }
    }

    return FinanceSummary(
      income: income,
      expense: expense,
      transactionCount: transactions.length,
      incomeByCategory: incomeByCategory,
      expenseByCategory: expenseByCategory,
    );
  }
}

/// Agrégat mensuel pour le mini-graphique du tableau de bord.
class MonthlyFlow {
  const MonthlyFlow({
    required this.month,
    required this.income,
    required this.expense,
  });

  final DateTime month;
  final int income;
  final int expense;

  int get balance => income - expense;

  String get label => month.shortFrenchMonth;

  String get key => month.ym;
}
