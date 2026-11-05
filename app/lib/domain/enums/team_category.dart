/// Catégories d'âge gérées par le club Dream Team New Hope.
///
/// Le [code] est la valeur **stable** persistée en base locale et envoyée vers
/// Google Sheets : il ne doit jamais changer, même si le libellé évolue.
enum TeamCategory {
  u12(code: 'U12', label: 'U12', ageRange: '8 - 11 ans'),
  u14u15(code: 'U14-U15', label: 'U14-U15', ageRange: '12 - 14 ans'),
  u16(code: 'U16', label: 'U16', ageRange: '15 - 16 ans'),
  u17u18(code: 'U17-U18', label: 'U17-U18', ageRange: '17 - 18 ans');

  const TeamCategory({
    required this.code,
    required this.label,
    required this.ageRange,
  });

  /// Identifiant stable (persistance locale + colonne `Catégorie` du Sheet).
  final String code;

  /// Libellé affiché dans l'interface.
  final String label;

  /// Tranche d'âge (affichée dans le sélecteur de catégorie).
  final String ageRange;

  /// Version courte pour les onglets étroits (ex : `U14/15`).
  String get shortLabel => code.replaceAll('-', '/');

  /// Retourne `null` si [code] est inconnu (au lieu de lever une exception :
  /// indispensable pour ne jamais perdre une donnée locale corrompue).
  static TeamCategory? tryParse(String? code) {
    if (code == null) return null;
    final normalized = code.trim().toUpperCase().replaceAll('/', '-');
    for (final category in TeamCategory.values) {
      if (category.code.toUpperCase() == normalized) return category;
      if (category.name.toUpperCase() == normalized) return category;
    }
    // Tolérance volontaire : "U14", "U15" -> U14-U15.
    if (normalized == 'U14' || normalized == 'U15' || normalized == 'U14U15') {
      return TeamCategory.u14u15;
    }
    if (normalized == 'U17' || normalized == 'U18' || normalized == 'U17U18') {
      return TeamCategory.u17u18;
    }
    return null;
  }

  static TeamCategory fromCode(String code) =>
      tryParse(code) ?? TeamCategory.u12;
}
