import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/common_widgets.dart';
import '../../di/providers.dart';
import '../../domain/enums/transaction_enums.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_controller.dart';
import 'finance_state.dart';
import 'new_transaction_sheet.dart';
import 'transactions_screen.dart';
import 'widgets/finance_widgets.dart';

/// Tableau de bord financier local (offline-first).
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  TransactionFlow _breakdownFlow = TransactionFlow.expense;

  @override
  Widget build(BuildContext context) {
    final total = ref.watch(totalSummaryProvider);
    final currentMonth = ref.watch(currentMonthSummaryProvider);
    final previousMonth = ref.watch(previousMonthSummaryProvider);
    final series = ref.watch(monthlySeriesProvider);
    final breakdown = ref.watch(categoryBreakdownProvider(_breakdownFlow));
    final recent = ref.watch(allTransactionsProvider).take(6).toList();
    final counters = ref.watch(syncCountersProvider);
    final syncState = ref.watch(syncControllerProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finances'),
        actions: [
          SyncStatusChip(
            pendingCount: counters.pending,
            errorCount: counters.error,
            isOnline: syncState.isOnline,
            isSyncing: syncState.isSyncing,
            onTap: () => _openTransactions(context),
          ),
          IconButton(
            tooltip: 'Configuration',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 92),
        children: [
          BalanceCard(
            balance: total.balance,
            monthIncome: currentMonth.income,
            monthExpense: currentMonth.expense,
            monthLabel: now.shortFrenchMonth,
          ),
          if (!syncState.isOnline)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: InfoBanner(
                message:
                    'Hors-ligne : vos saisies restent sur le téléphone et seront '
                    'envoyées au retour du réseau.',
                icon: Icons.cloud_off_rounded,
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FlowKpiCard(
                  label: 'Entrées du mois',
                  amount: currentMonth.income,
                  flow: TransactionFlow.income,
                  deltaPercent: _delta(currentMonth.income, previousMonth.income),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FlowKpiCard(
                  label: 'Sorties du mois',
                  amount: currentMonth.expense,
                  flow: TransactionFlow.expense,
                  deltaPercent:
                      _delta(currentMonth.expense, previousMonth.expense),
                ),
              ),
            ],
          ),
          const SectionHeader(
            title: 'Évolution sur 6 mois',
            subtitle: 'Entrées (vert) et sorties (rouge)',
          ),
          AppCard(
            child: MonthlyFlowChart(series: series),
          ),
          SectionHeader(
            title: 'Répartition des '
                '${_breakdownFlow == TransactionFlow.income ? 'entrées' : 'sorties'}',
            subtitle: 'Depuis le début de la saison',
          ),
          AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    for (final flow in TransactionFlow.values) ...[
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _breakdownFlow = flow),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _breakdownFlow == flow
                                  ? AppColors.navy
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                flow.label,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _breakdownFlow == flow
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (flow != TransactionFlow.values.last)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                CategoryBreakdownList(
                  entries: breakdown,
                  flow: _breakdownFlow,
                ),
              ],
            ),
          ),
          SectionHeader(
            title: 'Derniers mouvements',
            actionLabel: recent.isEmpty ? null : 'Tout voir',
            onAction: recent.isEmpty ? null : () => _openTransactions(context),
          ),
          if (recent.isEmpty)
            AppCard(
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Aucune opération',
                message:
                    'Les écolages, cotisations, billets et dépenses apparaîtront '
                    'ici. Tout est consultable hors-ligne.',
                actionLabel: 'Nouvelle transaction',
                onAction: () => openNewTransaction(context, ref),
              ),
            )
          else
            for (final transaction in recent)
              TransactionTile(
                transaction: transaction,
                onTap: () => openTransactionDetail(context, ref, transaction),
              ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openNewTransaction(context, ref),
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Nouvelle opération',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  int _delta(int current, int previous) {
    if (previous == 0) return current == 0 ? 0 : 100;
    return (((current - previous) / previous) * 100).round();
  }

  void _openTransactions(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TransactionsScreen()),
    );
  }
}
