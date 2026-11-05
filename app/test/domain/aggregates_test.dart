import 'package:dtnh_assistant_club/domain/entities/attendance_stats.dart';
import 'package:dtnh_assistant_club/domain/entities/finance_summary.dart';
import 'package:dtnh_assistant_club/domain/entities/financial_transaction.dart';
import 'package:dtnh_assistant_club/domain/enums/attendance_status.dart';
import 'package:dtnh_assistant_club/domain/enums/team_category.dart';
import 'package:dtnh_assistant_club/domain/enums/transaction_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttendanceStats', () {
    test('taux de présence effective = présents + retards', () {
      const stats = AttendanceStats(present: 8, absent: 2, late: 2, excused: 4);
      expect(stats.total, 16);
      expect(stats.attended, 10);
      expect(stats.rate, 0.625);
      expect(stats.ratePercent, 63);
      expect(stats.countFor(AttendanceStatus.excused), 4);
    });

    test('séries vides : pas de division par zéro', () {
      const stats = AttendanceStats();
      expect(stats.rate, 0);
      expect(stats.ratePercent, 0);
    });

    test('merge additionne les statuts', () {
      const a = AttendanceStats(present: 3, absent: 1);
      const b = AttendanceStats(present: 2, late: 4);
      final merged = a.merge(b);
      expect(merged.present, 5);
      expect(merged.late, 4);
      expect(merged.absent, 1);
      expect(merged.total, 10);
    });
  });

  group('FinanceSummary', () {
    FinancialTransaction tx({
      required String id,
      required TransactionFlow flow,
      required TransactionCategory category,
      required int amount,
    }) {
      final now = DateTime(2026, 11, 5);
      return FinancialTransaction(
        id: id,
        date: now,
        flow: flow,
        category: category,
        amount: amount,
        paymentMethod: PaymentMethod.cash,
        authorId: 'a1',
        authorName: 'Trésorier',
        createdAt: now,
        updatedAt: now,
      );
    }

    test('solde = entrées - sorties', () {
      final summary = FinanceSummary.from([
        tx(
          id: '1',
          flow: TransactionFlow.income,
          category: TransactionCategory.ecolage,
          amount: 120000,
        ),
        tx(
          id: '2',
          flow: TransactionFlow.income,
          category: TransactionCategory.billetterie,
          amount: 80000,
        ),
        tx(
          id: '3',
          flow: TransactionFlow.expense,
          category: TransactionCategory.locationTerrain,
          amount: 50000,
        ),
      ]);

      expect(summary.income, 200000);
      expect(summary.expense, 50000);
      expect(summary.balance, 150000);
      expect(summary.transactionCount, 3);
      expect(summary.incomeByCategory[TransactionCategory.ecolage], 120000);
      expect(
        summary.expenseByCategory[TransactionCategory.locationTerrain],
        50000,
      );
      expect(summary.isEmpty, isFalse);
    });

    test('synthèse vide', () {
      expect(FinanceSummary.empty.balance, 0);
      expect(FinanceSummary.empty.isEmpty, isTrue);
    });
  });

  group('FinancialTransaction', () {
    test('montant signé et résumé lisible', () {
      final now = DateTime(2026, 11, 5);
      final transaction = FinancialTransaction(
        id: 'x',
        date: now,
        flow: TransactionFlow.income,
        category: TransactionCategory.ecolage,
        amount: 60000,
        paymentMethod: PaymentMethod.mvola,
        playerName: 'Rasoa Miora',
        periodMonth: '2026-11',
        authorId: 'a1',
        authorName: 'Trésorier',
        createdAt: now,
        updatedAt: now,
      );

      expect(transaction.signedAmount, 60000);
      expect(transaction.isIncome, isTrue);
      expect(transaction.summary, 'Écolage · Rasoa Miora · nov. 2026');
      expect(transaction.periodLabel, 'nov. 2026');
    });
  });

  group('Enums', () {
    test('codes stables et parsing tolérant', () {
      expect(TeamCategory.u14u15.code, 'U14-U15');
      expect(TeamCategory.tryParse('u16'), TeamCategory.u16);
      expect(TeamCategory.fromCode('U15'), TeamCategory.u14u15);
      expect(AttendanceStatus.fromCode('PRESENT'), AttendanceStatus.present);
      expect(AttendanceStatus.fromCode('EN RETARD'), AttendanceStatus.late);
      expect(AttendanceStatus.fromCode('inconnu'), AttendanceStatus.absent);
      expect(PaymentMethod.fromCode('MVOLA'), PaymentMethod.mvola);
      expect(TransactionFlow.fromCode('IN'), TransactionFlow.income);
      expect(
        TransactionCategory.byFlow(TransactionFlow.expense).length,
        4,
      );
    });
  });
}
