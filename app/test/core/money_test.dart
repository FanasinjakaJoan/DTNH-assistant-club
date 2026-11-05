import 'package:dtnh_assistant_club/core/utils/date_x.dart';
import 'package:dtnh_assistant_club/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatAriary', () {
    test('sépare les milliers par espace', () {
      expect(formatAriary(0), '0 Ar');
      expect(formatAriary(60000), '60 000 Ar');
      expect(formatAriary(1250000), '1 250 000 Ar');
    });

    test('gère les montants négatifs (solde débiteur)', () {
      expect(formatAriary(-45000), '-45 000 Ar');
      expect(formatAriary(-45000, withSuffix: false), '-45 000');
    });
  });

  group('formatCompactAriary', () {
    test('compacte les millions et milliers', () {
      expect(formatCompactAriary(250000), '250 k Ar');
      expect(formatCompactAriary(1250000), '1,25 M Ar');
      expect(formatCompactAriary(2000000), '2 M Ar');
      expect(formatCompactAriary(-3000000), '-3 M Ar');
    });
  });

  group('parseAriary', () {
    test('ignore les séparateurs saisis par l\'utilisateur', () {
      expect(parseAriary('1 250 000'), 1250000);
      expect(parseAriary('1.250.000'), 1250000);
      expect(parseAriary('Ar 60 000'), 60000);
      expect(parseAriary(''), isNull);
      expect(parseAriary('abc'), isNull);
    });
  });

  group('groupDigits', () {
    test('groupe pendant la frappe', () {
      expect(groupDigits('60000'), '60 000');
      expect(groupDigits('1250000'), '1 250 000');
      expect(groupDigits('12'), '12');
      expect(groupDigits(''), '');
    });
  });

  group('safePercent', () {
    test('borne entre 0 et 1 et évite la division par zéro', () {
      expect(safePercent(3, 4), 0.75);
      expect(safePercent(5, 0), 0);
      expect(safePercent(9, 4), 1);
    });
  });

  group('date helpers', () {
    test('clés de date triables', () {
      final date = DateTime(2026, 11, 5, 8, 45);
      expect(date.ymd, '2026-11-05');
      expect(date.ym, '2026-11');
      expect(date.dmy, '05/11/2026');
      expect(date.hm, '08:45');
    });

    test('libellés français sans dépendance intl', () {
      final date = DateTime(2026, 11, 5);
      expect(date.longFrenchDate, 'jeudi 5 novembre 2026');
      expect(date.shortFrenchMonth, 'nov. 2026');
      expect(frenchMonthLabel('2026-11'), 'nov. 2026');
      expect(frenchMonthLabel('invalide'), 'invalide');
    });

    test('bornes de mois', () {
      final date = DateTime(2026, 2, 14, 10);
      expect(date.startOfMonth, DateTime(2026, 2));
      expect(date.endOfMonth.day, 28);
      expect(date.dateOnly, DateTime(2026, 2, 14));
    });
  });
}
