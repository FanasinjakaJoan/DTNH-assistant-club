import '../../core/utils/date_x.dart';
import '../enums/sync_enums.dart';
import '../enums/transaction_enums.dart';

/// Mouvement financier du club (entrée ou sortie).
///
/// Le montant est stocké en **Ariary entiers** (`int`) : l'ariary n'a pas de
/// sous-unité en usage courant, et l'entier supprime tout risque d'erreur
/// d'arrondi flottant dans les totaux.
class FinancialTransaction {
  const FinancialTransaction({
    required this.id,
    required this.date,
    required this.flow,
    required this.category,
    required this.amount,
    required this.paymentMethod,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    required this.updatedAt,
    this.details,
    this.playerName,
    this.staffName,
    this.eventName,
    this.periodMonth,
    this.syncState = SyncState.pending,
    this.syncedAt,
  });

  /// UUID v4 — clé primaire locale et clé d'idempotence côté Sheet.
  final String id;

  /// Date effective de l'opération (minuit local).
  final DateTime date;

  final TransactionFlow flow;
  final TransactionCategory category;

  /// Montant en Ariary, toujours positif (`flow` porte le sens).
  final int amount;

  final PaymentMethod paymentMethod;

  /// Remarque libre / description détaillée.
  final String? details;

  /// Joueur concerné (écolage, cotisation nominative).
  final String? playerName;

  /// Coach / membre du staff concerné (salaire, indemnité).
  final String? staffName;

  /// Événement concerné (billets, rafraîchissements).
  final String? eventName;

  /// Mois concerné au format `yyyy-MM` (écolage, salaire).
  final String? periodMonth;

  final String authorId;
  final String authorName;

  final DateTime createdAt;
  final DateTime updatedAt;

  final SyncState syncState;
  final DateTime? syncedAt;

  /// Montant signé : positif pour une entrée, négatif pour une sortie.
  int get signedAmount => amount * flow.sign;

  bool get isIncome => flow == TransactionFlow.income;

  String get periodLabel =>
      periodMonth == null ? '' : frenchMonthLabel(periodMonth!);

  FinancialTransaction copyWith({
    String? id,
    DateTime? date,
    TransactionFlow? flow,
    TransactionCategory? category,
    int? amount,
    PaymentMethod? paymentMethod,
    String? details,
    String? playerName,
    String? staffName,
    String? eventName,
    String? periodMonth,
    bool clearPeriod = false,
    String? authorId,
    String? authorName,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncState? syncState,
    DateTime? syncedAt,
    bool clearSyncedAt = false,
  }) {
    return FinancialTransaction(
      id: id ?? this.id,
      date: date ?? this.date,
      flow: flow ?? this.flow,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      details: details ?? this.details,
      playerName: playerName ?? this.playerName,
      staffName: staffName ?? this.staffName,
      eventName: eventName ?? this.eventName,
      periodMonth: clearPeriod ? null : (periodMonth ?? this.periodMonth),
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncState: syncState ?? this.syncState,
      syncedAt: clearSyncedAt ? null : (syncedAt ?? this.syncedAt),
    );
  }

  /// Résumé lisible : « Écolage · Rasoa Miora · nov. 2026 ».
  String get summary {
    final parts = <String>[
      category.label,
      if (playerName != null && playerName!.isNotEmpty) playerName!,
      if (staffName != null && staffName!.isNotEmpty) staffName!,
      if (eventName != null && eventName!.isNotEmpty) eventName!,
      if (periodMonth != null) frenchMonthLabel(periodMonth!),
    ];
    return parts.join(' · ');
  }

  @override
  String toString() => 'FinancialTransaction($id, $summary, $amount Ar)';
}
