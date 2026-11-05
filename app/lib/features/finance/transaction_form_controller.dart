import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/date_x.dart';
import '../../di/providers.dart';
import '../../domain/entities/financial_transaction.dart';
import '../../domain/enums/sync_enums.dart';
import '../../domain/enums/transaction_enums.dart';
import '../settings/settings_controller.dart';

/// État du formulaire de transaction (un formulaire dédié par motif).
class TransactionFormState {
  const TransactionFormState({
    required this.flow,
    required this.category,
    required this.date,
    required this.paymentMethod,
    this.amount = 0,
    this.playerName = '',
    this.staffName = '',
    this.eventName = '',
    this.periodMonth,
    this.details = '',
    this.isSaving = false,
    this.error,
    this.saved = false,
  });

  final TransactionFlow flow;
  final TransactionCategory category;
  final DateTime date;
  final int amount;
  final PaymentMethod paymentMethod;
  final String playerName;
  final String staffName;
  final String eventName;
  final String? periodMonth;
  final String details;
  final bool isSaving;
  final String? error;
  final bool saved;

  TransactionFormState copyWith({
    TransactionFlow? flow,
    TransactionCategory? category,
    DateTime? date,
    int? amount,
    PaymentMethod? paymentMethod,
    String? playerName,
    String? staffName,
    String? eventName,
    String? periodMonth,
    bool clearPeriod = false,
    String? details,
    bool? isSaving,
    String? error,
    bool clearError = false,
    bool? saved,
  }) {
    return TransactionFormState(
      flow: flow ?? this.flow,
      category: category ?? this.category,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      playerName: playerName ?? this.playerName,
      staffName: staffName ?? this.staffName,
      eventName: eventName ?? this.eventName,
      periodMonth: clearPeriod ? null : (periodMonth ?? this.periodMonth),
      details: details ?? this.details,
      isSaving: isSaving ?? this.isSaving,
      error: clearError ? null : (error ?? this.error),
      saved: saved ?? this.saved,
    );
  }
}

/// Provider **par motif** : ouvrir « Écolage » puis « Billet » ne partage
/// jamais l'état du formulaire.
final transactionFormProvider = NotifierProvider.family<
    TransactionFormController, TransactionFormState, TransactionCategory>(
  TransactionFormController.new,
);

class TransactionFormController
    extends FamilyNotifier<TransactionFormState, TransactionCategory> {
  bool _disposed = false;

  @override
  TransactionFormState build(TransactionCategory category) {
    ref.onDispose(() => _disposed = true);
    return _freshState(category);
  }

  /// Remet le formulaire à zéro (appelé à l'ouverture de l'écran).
  void reset() {
    if (_disposed) return;
    state = _freshState(arg);
  }

  void setAmount(int amount) =>
      state = state.copyWith(amount: amount, clearError: true);

  void setDate(DateTime date) =>
      state = state.copyWith(date: date.dateOnly, clearError: true);

  void setPaymentMethod(PaymentMethod method) =>
      state = state.copyWith(paymentMethod: method);

  void setPlayerName(String value) =>
      state = state.copyWith(playerName: value, clearError: true);

  void setStaffName(String value) =>
      state = state.copyWith(staffName: value, clearError: true);

  void setEventName(String value) =>
      state = state.copyWith(eventName: value, clearError: true);

  void setPeriodMonth(String? ym) => state = ym == null
      ? state.copyWith(clearPeriod: true, clearError: true)
      : state.copyWith(periodMonth: ym, clearError: true);

  void setDetails(String value) => state = state.copyWith(details: value);

  /// Validation métier : renvoie le premier message d'erreur, ou `null`.
  String? validate() {
    if (state.amount <= 0) {
      return 'Saisissez un montant supérieur à zéro.';
    }
    if (state.category.requiresPlayer && state.playerName.trim().isEmpty) {
      return 'Indiquez le joueur concerné.';
    }
    if (state.category.requiresStaff && state.staffName.trim().isEmpty) {
      return 'Indiquez le coach ou le membre du staff concerné.';
    }
    if (state.category.requiresEvent && state.eventName.trim().isEmpty) {
      return 'Précisez l\'événement (match, entraînement, tournoi…).';
    }
    if (state.category.requiresPeriod &&
        (state.periodMonth == null || state.periodMonth!.isEmpty)) {
      return 'Choisissez le mois concerné.';
    }
    return null;
  }

  /// Persiste localement + met en file de synchronisation.
  Future<bool> save() async {
    final validation = validate();
    if (validation != null) {
      state = state.copyWith(error: validation);
      return false;
    }

    final settings = ref.read(settingsProvider);
    if (!settings.hasAuthor) {
      state = state.copyWith(
        error: 'Aucun auteur défini : renseignez votre nom dans les réglages.',
      );
      return false;
    }

    state = state.copyWith(isSaving: true, clearError: true);
    final now = DateTime.now();
    final transaction = FinancialTransaction(
      id: const Uuid().v4(),
      date: state.date,
      flow: state.flow,
      category: state.category,
      amount: state.amount,
      paymentMethod: state.paymentMethod,
      details: state.details.trim().isEmpty ? null : state.details.trim(),
      playerName:
          state.playerName.trim().isEmpty ? null : state.playerName.trim(),
      staffName:
          state.staffName.trim().isEmpty ? null : state.staffName.trim(),
      eventName:
          state.eventName.trim().isEmpty ? null : state.eventName.trim(),
      periodMonth: state.periodMonth,
      authorId: settings.authorId!,
      authorName: settings.authorName!,
      createdAt: now,
      updatedAt: now,
      syncState: SyncState.pending,
    );

    try {
      await ref.read(transactionRepositoryProvider).save(transaction);
      if (_disposed) return true;
      state = state.copyWith(isSaving: false, saved: true);
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        isSaving: false,
        error: 'Échec de l\'enregistrement local : $error',
      );
      return false;
    }
  }

  TransactionFormState _freshState(TransactionCategory category) {
    final now = DateTime.now();
    return TransactionFormState(
      flow: category.flow,
      category: category,
      date: DateTime(now.year, now.month, now.day),
      paymentMethod: PaymentMethod.cash,
      periodMonth: category.requiresPeriod ? now.ym : null,
    );
  }
}
