import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/entities/financial_transaction.dart';
import '../../domain/enums/transaction_enums.dart';
import '../settings/settings_controller.dart';
import '../sync/sync_controller.dart';
import 'transaction_form_screen.dart';
import 'widgets/finance_widgets.dart';

/// Sélection du type d'opération puis du motif (formulaire dédié).
///
/// Le suivi post-enregistrement (message + synchronisation) est fait ici avec le
/// `WidgetRef` de l'écran appelant, qui reste monté après la fermeture du
/// formulaire.
Future<void> openNewTransaction(
  BuildContext context,
  WidgetRef ref,
) async {
  final category = await showModalBottomSheet<TransactionCategory>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _NewTransactionSheet(),
  );
  if (category == null || !context.mounted) return;

  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => TransactionFormScreen(category: category),
    ),
  );
  if (saved != true || !context.mounted) return;

  showAppSnack(
    context,
    '${category.label} enregistré · en attente de synchronisation.',
    icon: Icons.check_circle_rounded,
    actionLabel: 'Synchroniser',
    onAction: () => ref.read(syncControllerProvider.notifier).syncNow(),
  );

  final settings = ref.read(settingsProvider);
  if (settings.autoSyncEnabled && ref.read(syncControllerProvider).isOnline) {
    ref.read(syncControllerProvider.notifier).syncNow();
  }
}

/// Détail + suppression d'une transaction existante.
Future<void> openTransactionDetail(
  BuildContext context,
  WidgetRef ref,
  FinancialTransaction transaction,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => TransactionDetailSheet(
      transaction: transaction,
      onDelete: () async {
        Navigator.of(sheetContext).pop();
        await ref.read(transactionRepositoryProvider).delete(transaction.id);
        if (!context.mounted) return;
        showAppSnack(
          context,
          'Opération supprimée (localement et à la prochaine synchronisation).',
          icon: Icons.delete_outline_rounded,
        );
      },
    ),
  );
}

class _NewTransactionSheet extends StatelessWidget {
  const _NewTransactionSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        maxChildSize: 0.92,
        minChildSize: 0.5,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
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
            const Text(
              'Nouvelle opération',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choisissez le motif : chaque formulaire ne demande que les '
              'champs utiles.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
            for (final flow in TransactionFlow.values) ...[
              SectionHeader(
                title: flow == TransactionFlow.income
                    ? 'Entrées d\'argent'
                    : 'Sorties d\'argent',
                subtitle: flow == TransactionFlow.income
                    ? 'Écolages, cotisations, billetterie'
                    : 'Terrain, coachs, rafraîchissements',
                padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
              ),
              for (final category in TransactionCategory.byFlow(flow))
                _CategoryOption(
                  category: category,
                  onTap: () => Navigator.of(context).pop(category),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryOption extends StatelessWidget {
  const _CategoryOption({required this.category, required this.onTap});

  final TransactionCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = colorForFlow(category.flow);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
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
                  iconForTransactionCategory(category),
                  size: 19,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      category.description,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

