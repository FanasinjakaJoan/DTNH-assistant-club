import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/common_widgets.dart';
import '../../di/providers.dart';
import '../../domain/enums/transaction_enums.dart';
import 'finance_state.dart';
import 'new_transaction_sheet.dart';
import 'widgets/finance_widgets.dart';

/// Liste complète des mouvements avec recherche et filtres.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() =>
      _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(financeFilterProvider);
    final transactions = ref.watch(filteredTransactionsProvider);
    final summary = ref.watch(filteredSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mouvements'),
        actions: [
          IconButton(
            tooltip: 'Filtrer',
            onPressed: () => _openFilters(context, filter),
            icon: Badge(
              isLabelVisible: filter.isActive,
              backgroundColor: AppColors.orange,
              child: const Icon(Icons.tune_rounded),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => ref
                  .read(financeFilterProvider.notifier)
                  .state = ref
                      .read(financeFilterProvider)
                      .copyWith(search: value),
              decoration: InputDecoration(
                hintText: 'Rechercher (joueur, motif, auteur…)',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: filter.search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(financeFilterProvider.notifier).state = ref
                              .read(financeFilterProvider)
                              .copyWith(search: '');
                        },
                      ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          if (filter.isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _filterLabel(filter),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ref.read(financeFilterProvider.notifier).state =
                          const FinanceFilter();
                      _searchController.clear();
                    },
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('Effacer'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Text(
                    '${transactions.length} opération(s)',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '+${formatCompactAriary(summary.income)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.income,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '-${formatCompactAriary(summary.expense)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.expense,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: transactions.isEmpty
                ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Aucun mouvement',
                    message: filter.isActive
                        ? 'Aucun résultat pour ce filtre. Essayez une autre '
                            'période ou un autre motif.'
                        : 'Les opérations apparaîtront ici dès la première '
                            'saisie.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final transaction = transactions[index];
                      return TransactionTile(
                        transaction: transaction,
                        onTap: () => openTransactionDetail(
                          context,
                          ref,
                          transaction,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openNewTransaction(context, ref),
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Ajouter',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> _openFilters(BuildContext context, FinanceFilter filter) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FinanceFilterSheet(
        flow: filter.flow,
        category: filter.category,
        month: filter.month,
        onFlowChanged: (flow) => _update(
          flow == null ? filter.copyWith(clearFlow: true) : filter.copyWith(flow: flow),
        ),
        onCategoryChanged: (category) => _update(
          category == null
              ? filter.copyWith(clearCategory: true)
              : filter.copyWith(category: category),
        ),
        onMonthChanged: (month) => _update(
          month == null
              ? filter.copyWith(clearMonth: true)
              : filter.copyWith(month: month),
        ),
        onReset: () => _update(const FinanceFilter()),
      ),
    );
  }

  void _update(FinanceFilter filter) {
    final current = ref.read(financeFilterProvider);
    ref.read(financeFilterProvider.notifier).state =
        filter.copyWith(search: current.search);
  }

  String _filterLabel(FinanceFilter filter) {
    final parts = <String>[
      if (filter.flow != null) filter.flow!.label,
      if (filter.month != null) filter.month!,
      if (filter.category != null) filter.category!.label,
    ];
    if (parts.isEmpty) return 'Recherche : "${filter.search}"';
    return parts.join(' · ');
  }
}
