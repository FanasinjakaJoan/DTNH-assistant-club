import 'dart:math' as math;

/// Formatage monétaire en Ariary (Ar).
///
/// L'ariary n'a pas de sous-unité utilisée au quotidien : on manipule des
/// entiers et on n'affiche jamais de décimales.
String formatAriary(int amount, {bool withSuffix = true}) {
  final isNegative = amount < 0;
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  final formatted = buffer.toString();
  final signed = isNegative ? '-$formatted' : formatted;
  return withSuffix ? '$signed Ar' : signed;
}

/// Format compact pour les cartes du tableau de bord : `1,25 M Ar`.
String formatCompactAriary(int amount) {
  final abs = amount.abs();
  final sign = amount < 0 ? '-' : '';
  if (abs >= 1000000) {
    return '$sign${_trim(abs / 1000000)} M Ar';
  }
  if (abs >= 1000) {
    return '$sign${_trim(abs / 1000, digits: 0)} k Ar';
  }
  return '$sign$abs Ar';
}

String _trim(double value, {int digits = 2}) {
  var text = value.toStringAsFixed(digits);
  if (text.contains('.')) {
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }
  }
  return text.replaceAll('.', ',');
}

/// Extrait un entier depuis une saisie utilisateur (`1 200 000`, `1.200.000`).
int? parseAriary(String input) {
  final cleaned = input.replaceAll(RegExp('[^0-9]'), '');
  if (cleaned.isEmpty) return null;
  return int.tryParse(cleaned);
}

/// Sépare les milliers pendant la frappe : `1250000` -> `1 250 000`.
String groupDigits(String input) {
  final digits = input.replaceAll(RegExp('[^0-9]'), '');
  if (digits.isEmpty) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Pourcentage borné à [0, 1] pour les jauges de présence.
double safePercent(num value, num total) {
  if (total <= 0) return 0;
  return (value / total).clamp(0, 1).toDouble();
}

/// Moyenne sûre (évite la division par zéro dans les synthèses).
double safeAverage(Iterable<num> values) {
  final list = values.toList();
  if (list.isEmpty) return 0;
  final sum = list.fold<num>(0, (a, b) => a + b);
  return sum / list.length;
}

/// Arrondi au millier supérieur (budgets).
int ceilToThousand(int amount) => (amount / 1000).ceil() * 1000;

/// `min` réexporté pour éviter un import `dart:math` dans les widgets de graphe.
int minInt(int a, int b) => math.min(a, b);
