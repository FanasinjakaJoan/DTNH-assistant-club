import 'package:flutter/material.dart';

/// Palette DTNH : navy profond (identité club) + orange basket (action).
///
/// Les couleurs de statut sont **sémantiques** et ne doivent pas être utilisées
/// pour la décoration : vert = présent, rouge = absent, ambre = retard,
/// bleu = excusé. Cela permet au coach de lire l'écran sans lire les libellés.
class AppColors {
  const AppColors._();

  static const Color navy = Color(0xFF0F172A);
  static const Color navyLight = Color(0xFF1E293B);
  static const Color orange = Color(0xFFF97316);
  static const Color orangeSoft = Color(0xFFFFEDD5);
  static const Color orangeDark = Color(0xFFC2410C);

  static const Color green = Color(0xFF16A34A);
  static const Color greenSoft = Color(0xFFDCFCE7);
  static const Color red = Color(0xFFDC2626);
  static const Color redSoft = Color(0xFFFEE2E2);
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberSoft = Color(0xFFFEF3C7);
  static const Color blue = Color(0xFF2563EB);
  static const Color blueSoft = Color(0xFFDBEAFE);

  static const Color surface = Color(0xFFF5F7FA);
  static const Color card = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);

  static const Color income = green;
  static const Color expense = red;

  static const LinearGradient balanceGradient = LinearGradient(
    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient orangeGradient = LinearGradient(
    colors: [Color(0xFFF97316), Color(0xFFEA580C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
