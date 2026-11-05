/// Statut de présence d'un joueur pour une séance donnée.
///
/// [code] est la valeur envoyée dans la colonne `Statut` de l'onglet
/// `Présences` ; les libellés français servent à l'UI et aux exports CSV.
enum AttendanceStatus {
  present(
    code: 'PRESENT',
    label: 'Présent',
    shortLabel: 'P',
    countsAsPresent: true,
  ),
  absent(
    code: 'ABSENT',
    label: 'Absent',
    shortLabel: 'A',
    countsAsPresent: false,
  ),
  retard(
    code: 'LATE',
    label: 'En retard',
    shortLabel: 'R',
    countsAsPresent: true,
  ),
  excused(
    code: 'EXCUSED',
    label: 'Excusé',
    shortLabel: 'E',
    countsAsPresent: false,
  );

  const AttendanceStatus({
    required this.code,
    required this.label,
    required this.shortLabel,
    required this.countsAsPresent,
  });

  final String code;
  final String label;

  /// Lettre utilisée dans les vues compactes (statistiques, historique).
  final String shortLabel;

  /// `true` pour les statuts comptabilisés comme une présence effective
  /// (présent + retard), afin de calculer un taux de présence juste.
  final bool countsAsPresent;

  static AttendanceStatus? tryParse(String? code) {
    if (code == null) return null;
    final normalized = code.trim().toUpperCase();
    for (final status in AttendanceStatus.values) {
      if (status.code == normalized || status.name.toUpperCase() == normalized) {
        return status;
      }
    }
    // Tolérance sur les libellés français renvoyés par un Sheet existant.
    switch (normalized) {
      case 'PRÉSENT':
      case 'PRESENT':
        return AttendanceStatus.present;
      case 'RETARD':
      case 'EN RETARD':
        return AttendanceStatus.retard;
      case 'EXCUSÉ':
      case 'EXCUSE':
        return AttendanceStatus.excused;
      case 'ABSENT':
        return AttendanceStatus.absent;
      default:
        return null;
    }
  }

  static AttendanceStatus fromCode(String? code) =>
      tryParse(code) ?? AttendanceStatus.absent;
}
