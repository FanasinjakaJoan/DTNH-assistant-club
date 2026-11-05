/// Helpers de date partagés par toutes les couches (shared kernel).
///
/// Les dates métier sont manipulées en **heure locale** ; la sérialisation
/// utilise des clés `yyyy-MM-dd` (tri lexicographique = tri chronologique).
extension DateX on DateTime {
  /// `2026-11-05`
  String get ymd =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// `2026-11`
  String get ym =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  /// `05/11/2026`
  String get dmy =>
      '${day.toString().padLeft(2, '0')}/'
      '${month.toString().padLeft(2, '0')}/$year';

  /// `08:45`
  String get hm =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// `2026-11-05T08:45:12.000`
  String get iso => toIso8601String();

  /// Minuit local du même jour.
  DateTime get dateOnly => DateTime(year, month, day);

  bool isSameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  bool isSameMonth(DateTime other) => year == other.year && month == other.month;

  /// Premier jour du mois à minuit.
  DateTime get startOfMonth => DateTime(year, month);

  /// Dernier instant du mois (utile pour les bornes de requête).
  DateTime get endOfMonth => DateTime(year, month + 1, 0, 23, 59, 59, 999);

  /// `lundi 5 novembre 2026` (sans dépendance à `intl` dans le domaine).
  String get longFrenchDate {
    const days = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche',
    ];
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    return '${days[weekday - 1]} $day ${months[month - 1]} $year';
  }

  /// `nov. 2026`
  String get shortFrenchMonth {
    const months = [
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.',
    ];
    return '${months[month - 1]} $year';
  }
}

/// `2026-11` -> `novembre 2026`
String frenchMonthLabel(String ym) {
  final parts = ym.split('-');
  if (parts.length != 2) return ym;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return ym;
  return DateTime(year, month).shortFrenchMonth;
}
