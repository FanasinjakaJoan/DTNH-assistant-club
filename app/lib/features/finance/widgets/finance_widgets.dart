import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/status_styles.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../domain/entities/finance_summary.dart';
import '../../../domain/entities/financial_transaction.dart';
import '../../../domain/enums/transaction_enums.dart';

/// Carte « solde du club » (hero du dashboard financier).
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.balance,
    required this.monthIncome,
    required this.monthExpense,
    required this.monthLabel,
  });

  final int balance;
  final int monthIncome;
  final int monthExpense;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        gradient: AppColors.balanceGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              const Text(
                'Solde du club',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  monthLabel,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatAriary(balance),
              style: const TextStyle(
                fontSize: 32,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniFlow(
                  label: 'Entrées',
                  amount: monthIncome,
                  icon: Icons.south_west_rounded,
                  color: const Color(0xFF4ADE80),
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: Colors.white.withOpacity(0.12),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniFlow(
                  label: 'Sorties',
                  amount: monthExpense,
                  icon: Icons.north_east_rounded,
                  color: const Color(0xFFFCA5A5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniFlow extends StatelessWidget {
  const _MiniFlow({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String label;
  final int amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withOpacity(0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Colors.white60,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                formatCompactAriary(amount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Petite tuile KPI (entrées / sorties du mois).
class FlowKpiCard extends StatelessWidget {
  const FlowKpiCard({
    super.key,
    required this.label,
    required this.amount,
    required this.flow,
    this.deltaPercent,
  });

  final String label;
  final int amount;
  final TransactionFlow flow;
  final int? deltaPercent;

  @override
  Widget build(BuildContext context) {
    final color = colorForFlow(flow);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  flow == TransactionFlow.income
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  size: 14,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatAriary(amount),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (deltaPercent != null) ...[
            const SizedBox(height: 4),
            Text(
              deltaPercent! == 0
                  ? 'Stable vs mois dernier'
                  : '${deltaPercent! > 0 ? '+' : ''}$deltaPercent % vs mois dernier',
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mini graphique entrées/sorties sur 6 mois (dessiné à la main, sans lib).
class MonthlyFlowChart extends StatelessWidget {
  const MonthlyFlowChart({super.key, required this.series});

  final List<MonthlyFlow> series;

  @override
  Widget build(BuildContext context) {
    final maxValue = series.fold<int>(
      1,
      (max, flow) => [
        max,
        flow.income,
        flow.expense,
      ].reduce((a, b) => a > b ? a : b),
    );

    return SizedBox(
      height: 148,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final flow in series)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Bar(
                            value: flow.income,
                            maxValue: maxValue,
                            color: AppColors.income,
                          ),
                          const SizedBox(width: 3),
                          _Bar(
                            value: flow.expense,
                            maxValue: maxValue,
                            color: AppColors.expense,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      flow.label.split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final int value;
  final int maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue == 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return Tooltip(
      message: formatAriary(value),
      child: Container(
        width: 9,
        constraints: const BoxConstraints(minHeight: 2),
        height: (ratio * 90) + 2,
        decoration: BoxDecoration(
          color: value == 0 ? AppColors.border : color,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// Répartition par motif (barres horizontales).
class CategoryBreakdownList extends StatelessWidget {
  const CategoryBreakdownList({
    super.key,
    required this.entries,
    required this.flow,
  });

  final List<MapEntry<TransactionCategory, int>> entries;
  final TransactionFlow flow;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'Aucun mouvement enregistré pour cette période.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      );
    }
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    final color = colorForFlow(flow);

    return Column(
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      iconForTransactionCategory(entry.key),
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        entry.key.label,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      formatCompactAriary(entry.value),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : entry.value / total,
                    minHeight: 6,
                    backgroundColor: AppColors.surface,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ligne de transaction (liste des mouvements).
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTap,
  });

  final FinancialTransaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = colorForFlow(transaction.flow);
    final syncVisual = visualForSync(transaction.syncState);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  iconForTransactionCategory(transaction.category),
                  size: 19,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(transaction),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${transaction.isIncome ? '+' : '-'}${formatAriary(transaction.amount, withSuffix: false)}',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        syncVisual.icon,
                        size: 11,
                        color: syncVisual.color,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        transaction.date.dmy,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(FinancialTransaction tx) {
    final parts = <String>[
      if (tx.playerName != null && tx.playerName!.isNotEmpty) tx.playerName!,
      if (tx.staffName != null && tx.staffName!.isNotEmpty) tx.staffName!,
      if (tx.eventName != null && tx.eventName!.isNotEmpty) tx.eventName!,
      if (tx.periodMonth != null) frenchMonthLabel(tx.periodMonth!),
      tx.paymentMethod.label,
      if (tx.details != null && tx.details!.isNotEmpty) tx.details!,
    ];
    return parts.join(' · ');
  }
}

/// Feuille de filtres des mouvements.
class FinanceFilterSheet extends StatelessWidget {
  const FinanceFilterSheet({
    super.key,
    required this.flow,
    required this.category,
    required this.month,
    required this.onFlowChanged,
    required this.onCategoryChanged,
    required this.onMonthChanged,
    required this.onReset,
  });

  final TransactionFlow? flow;
  final TransactionCategory? category;
  final String? month;
  final ValueChanged<TransactionFlow?> onFlowChanged;
  final ValueChanged<TransactionCategory?> onCategoryChanged;
  final ValueChanged<String?> onMonthChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = List<String>.generate(
      6,
      (index) => DateTime(now.year, now.month - index).ym,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Filtrer les mouvements',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(onPressed: onReset, child: const Text('Réinitialiser')),
              ],
            ),
            const SizedBox(height: 8),
            const _FilterLabel('Sens'),
            Wrap(
              spacing: 8,
              children: [
                _ChoiceChip(
                  label: 'Tous',
                  selected: flow == null,
                  onTap: () => onFlowChanged(null),
                ),
                for (final value in TransactionFlow.values)
                  _ChoiceChip(
                    label: value.label,
                    selected: flow == value,
                    color: colorForFlow(value),
                    onTap: () => onFlowChanged(value),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const _FilterLabel('Mois'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ChoiceChip(
                  label: 'Tous',
                  selected: month == null,
                  onTap: () => onMonthChanged(null),
                ),
                for (final value in months)
                  _ChoiceChip(
                    label: frenchMonthLabel(value),
                    selected: month == value,
                    onTap: () => onMonthChanged(value),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const _FilterLabel('Motif'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ChoiceChip(
                  label: 'Tous',
                  selected: category == null,
                  onTap: () => onCategoryChanged(null),
                ),
                for (final value in TransactionCategory.values)
                  _ChoiceChip(
                    label: value.label,
                    selected: category == value,
                    onTap: () => onCategoryChanged(value),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.navy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? accent : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? accent : AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Détail d'une transaction (bottom sheet).
class TransactionDetailSheet extends StatelessWidget {
  const TransactionDetailSheet({
    super.key,
    required this.transaction,
    required this.onDelete,
  });

  final FinancialTransaction transaction;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = colorForFlow(transaction.flow);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    iconForTransactionCategory(transaction.category),
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.category.label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${transaction.flow.label} · ${transaction.date.dmy}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${transaction.isIncome ? '+' : '-'}${formatAriary(transaction.amount, withSuffix: false)} Ar',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(),
            DetailRow(
              label: 'Mode de paiement',
              value: transaction.paymentMethod.label,
              icon: iconForPaymentMethod(transaction.paymentMethod),
            ),
            if (transaction.playerName != null)
              DetailRow(
                label: 'Joueur',
                value: transaction.playerName!,
                icon: Icons.person_rounded,
              ),
            if (transaction.staffName != null)
              DetailRow(
                label: 'Coach / staff',
                value: transaction.staffName!,
                icon: Icons.sports_rounded,
              ),
            if (transaction.eventName != null)
              DetailRow(
                label: 'Événement',
                value: transaction.eventName!,
                icon: Icons.event_rounded,
              ),
            if (transaction.periodMonth != null)
              DetailRow(
                label: 'Mois concerné',
                value: frenchMonthLabel(transaction.periodMonth!),
                icon: Icons.calendar_month_rounded,
              ),
            if (transaction.details != null)
              DetailRow(
                label: 'Remarque',
                value: transaction.details!,
                icon: Icons.sticky_note_2_rounded,
              ),
            DetailRow(
              label: 'Saisi par',
              value: transaction.authorName,
              icon: Icons.badge_rounded,
            ),
            DetailRow(
              label: 'Synchronisation',
              value: transaction.syncState.label,
              icon: visualForSync(transaction.syncState).icon,
              valueColor: visualForSync(transaction.syncState).color,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Supprimer cette opération'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red,
                side: const BorderSide(color: AppColors.redSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
