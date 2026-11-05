import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../core/utils/date_x.dart';
import '../../core/widgets/amount_field.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/date_picker_sheet.dart';
import '../../di/providers.dart';
import '../../domain/enums/transaction_enums.dart';
import '../settings/settings_controller.dart';
import 'transaction_form_controller.dart';

/// Formulaire dédié à un motif : seuls les champs pertinents sont affichés.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, required this.category});

  final TransactionCategory category;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState
    extends ConsumerState<TransactionFormScreen> {
  final TextEditingController _playerController = TextEditingController();
  final TextEditingController _staffController = TextEditingController();
  final TextEditingController _eventController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Repart d'un formulaire vierge (le provider est mis en cache par motif).
    ref
        .read(transactionFormProvider(widget.category).notifier)
        .reset();
  }

  @override
  void dispose() {
    _playerController.dispose();
    _staffController.dispose();
    _eventController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = transactionFormProvider(widget.category);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final settings = ref.watch(settingsProvider);
    final category = widget.category;
    final players = ref.watch(playersStreamProvider).valueOrNull ?? const [];
    final playerSuggestions = players
        .map((player) => player.fullName)
        .toSet()
        .take(8)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(category.flow == TransactionFlow.income
                ? 'Entrée d\'argent'
                : 'Sortie d\'argent'),
            Text(
              category.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorForFlow(category.flow).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  category.flow.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: colorForFlow(category.flow),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
        children: [
          AppCard(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorForFlow(category.flow).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    iconForTransactionCategory(category),
                    color: colorForFlow(category.flow),
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
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
              ],
            ),
          ),
          const SizedBox(height: 14),
          AmountField(
            amount: state.amount,
            onChanged: controller.setAmount,
          ),
          const SizedBox(height: 14),
          _FieldLabel('Date de l\'opération'),
          _PickerTile(
            icon: Icons.event_rounded,
            label: state.date.longFrenchDate,
            onTap: () async {
              final picked = await showAppDatePicker(
                context,
                initialDate: state.date,
              );
              if (picked != null) controller.setDate(picked);
            },
          ),
          const SizedBox(height: 14),
          _FieldLabel('Mode de paiement'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final method in PaymentMethod.values)
                _PillChoice(
                  label: method.label,
                  icon: iconForPaymentMethod(method),
                  selected: state.paymentMethod == method,
                  onTap: () => controller.setPaymentMethod(method),
                ),
            ],
          ),
          if (category.requiresPlayer) ...[
            const SizedBox(height: 14),
            _FieldLabel('Joueur concerné'),
            TextField(
              controller: _playerController,
              textCapitalization: TextCapitalization.words,
              onChanged: controller.setPlayerName,
              decoration: const InputDecoration(
                hintText: 'Nom et prénom du joueur',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            if (playerSuggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in playerSuggestions)
                      _PillChoice(
                        label: name,
                        selected: false,
                        onTap: () {
                          _playerController.text = name;
                          controller.setPlayerName(name);
                        },
                      ),
                  ],
                ),
              ),
          ],
          if (category.requiresStaff) ...[
            const SizedBox(height: 14),
            _FieldLabel('Coach / membre du staff'),
            TextField(
              controller: _staffController,
              textCapitalization: TextCapitalization.words,
              onChanged: controller.setStaffName,
              decoration: const InputDecoration(
                hintText: 'Nom du coach',
                prefixIcon: Icon(Icons.sports_rounded),
              ),
            ),
          ],
          if (category.requiresEvent) ...[
            const SizedBox(height: 14),
            _FieldLabel('Événement'),
            TextField(
              controller: _eventController,
              textCapitalization: TextCapitalization.sentences,
              onChanged: controller.setEventName,
              decoration: const InputDecoration(
                hintText: 'Match U16 · Tournoi de Mahamasina…',
                prefixIcon: Icon(Icons.stadium_rounded),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final label in const [
                    'Match',
                    'Entraînement',
                    'Tournoi',
                    'Déplacement',
                  ])
                    _PillChoice(
                      label: label,
                      selected: false,
                      onTap: () {
                        _eventController.text = label;
                        controller.setEventName(label);
                      },
                    ),
                ],
              ),
            ),
          ],
          if (category.requiresPeriod) ...[
            const SizedBox(height: 14),
            _FieldLabel(category == TransactionCategory.salaireCoach
                ? 'Mois rémunéré'
                : 'Mois concerné'),
            _MonthSelector(
              selected: state.periodMonth,
              onChanged: controller.setPeriodMonth,
            ),
          ],
          const SizedBox(height: 14),
          _FieldLabel('Remarque (facultatif)'),
          TextField(
            controller: _detailsController,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            onChanged: controller.setDetails,
            decoration: const InputDecoration(
              hintText: 'Précision utile pour le trésorier…',
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            color: AppColors.surface,
            borderColor: AppColors.border,
            child: Row(
              children: [
                const Icon(
                  Icons.badge_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Saisi par ${settings.authorName ?? "—"}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 15,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Enregistré localement',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: InfoBanner(
                message: state.error!,
                icon: Icons.error_outline_rounded,
                color: AppColors.red,
                background: AppColors.redSoft,
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: LoadingButton(
              label: state.isSaving ? 'Enregistrement' : 'Enregistrer l\'opération',
              icon: Icons.check_rounded,
              loading: state.isSaving,
              onPressed: () => _save(controller),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save(TransactionFormController controller) async {
    final success = await controller.save();
    if (!mounted) return;
    if (!success) {
      final error = ref.read(transactionFormProvider(widget.category)).error;
      if (error != null) {
        showAppSnack(
          context,
          error,
          color: AppColors.red,
          icon: Icons.error_outline_rounded,
        );
      }
      return;
    }
    // L'écran appelant se charge du message et de la synchronisation.
    Navigator.of(context).pop(true);
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
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

class _PillChoice extends StatelessWidget {
  const _PillChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.navy : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.navy : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final months = List<String>.generate(
      12,
      (index) => DateTime(year, index + 1).ym,
    );

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final ym in months)
          _PillChoice(
            label: frenchMonthLabel(ym).split(' ').first,
            selected: selected == ym,
            onTap: () => onChanged(ym),
          ),
      ],
    );
  }
}
