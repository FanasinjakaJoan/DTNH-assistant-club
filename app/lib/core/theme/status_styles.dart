import 'package:flutter/material.dart';

import '../../domain/enums/attendance_status.dart';
import '../../domain/enums/sync_enums.dart';
import '../../domain/enums/transaction_enums.dart';
import 'app_colors.dart';

/// Habillage visuel d'un statut : couleur pleine, fond doux, icône.
class StatusVisual {
  const StatusVisual({
    required this.color,
    required this.background,
    required this.icon,
    required this.label,
  });

  final Color color;
  final Color background;
  final IconData icon;
  final String label;
}

StatusVisual visualForAttendance(AttendanceStatus status) {
  switch (status) {
    case AttendanceStatus.present:
      return const StatusVisual(
        color: AppColors.green,
        background: AppColors.greenSoft,
        icon: Icons.check_rounded,
        label: 'Présent',
      );
    case AttendanceStatus.absent:
      return const StatusVisual(
        color: AppColors.red,
        background: AppColors.redSoft,
        icon: Icons.close_rounded,
        label: 'Absent',
      );
    case AttendanceStatus.retard:
      return const StatusVisual(
        color: AppColors.amber,
        background: AppColors.amberSoft,
        icon: Icons.schedule_rounded,
        label: 'En retard',
      );
    case AttendanceStatus.excused:
      return const StatusVisual(
        color: AppColors.blue,
        background: AppColors.blueSoft,
        icon: Icons.verified_rounded,
        label: 'Excusé',
      );
  }
}

StatusVisual visualForSync(SyncState state) {
  switch (state) {
    case SyncState.pending:
      return const StatusVisual(
        color: AppColors.amber,
        background: AppColors.amberSoft,
        icon: Icons.cloud_upload_outlined,
        label: 'En attente',
      );
    case SyncState.synced:
      return const StatusVisual(
        color: AppColors.green,
        background: AppColors.greenSoft,
        icon: Icons.cloud_done_rounded,
        label: 'Synchronisé',
      );
    case SyncState.error:
      return const StatusVisual(
        color: AppColors.red,
        background: AppColors.redSoft,
        icon: Icons.cloud_off_rounded,
        label: 'Erreur',
      );
  }
}

IconData iconForTransactionCategory(TransactionCategory category) {
  switch (category) {
    case TransactionCategory.ecolage:
      return Icons.school_rounded;
    case TransactionCategory.cotisation:
      return Icons.groups_rounded;
    case TransactionCategory.billetterie:
      return Icons.confirmation_number_rounded;
    case TransactionCategory.autreEntree:
      return Icons.savings_rounded;
    case TransactionCategory.locationTerrain:
      return Icons.stadium_rounded;
    case TransactionCategory.salaireCoach:
      return Icons.sports_rounded;
    case TransactionCategory.rafraichissement:
      return Icons.local_drink_rounded;
    case TransactionCategory.autreSortie:
      return Icons.receipt_long_rounded;
  }
}

IconData iconForPaymentMethod(PaymentMethod method) {
  switch (method) {
    case PaymentMethod.cash:
      return Icons.payments_rounded;
    case PaymentMethod.mvola:
    case PaymentMethod.orangeMoney:
    case PaymentMethod.airtelMoney:
      return Icons.phone_android_rounded;
    case PaymentMethod.bankTransfer:
      return Icons.account_balance_rounded;
    case PaymentMethod.cheque:
      return Icons.description_rounded;
    case PaymentMethod.other:
      return Icons.more_horiz_rounded;
  }
}

Color colorForFlow(TransactionFlow flow) =>
    flow == TransactionFlow.income ? AppColors.income : AppColors.expense;

/// Couleur stable par catégorie d'âge (repère visuel rapide en bord de terrain).
Color colorForCategoryIndex(int index) {
  const palette = <Color>[
    Color(0xFF0EA5E9), // U12  - bleu ciel
    Color(0xFF8B5CF6), // U14/15 - violet
    Color(0xFFF97316), // U16  - orange
    Color(0xFF10B981), // U17/18 - émeraude
  ];
  return palette[index % palette.length];
}
