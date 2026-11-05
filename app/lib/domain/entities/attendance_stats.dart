import '../enums/attendance_status.dart';
import '../enums/team_category.dart';

/// Agrégat de présences (par joueur, par catégorie ou par période).
class AttendanceStats {
  const AttendanceStats({
    this.present = 0,
    this.absent = 0,
    this.late = 0,
    this.excused = 0,
  });

  final int present;
  final int absent;
  final int late;
  final int excused;

  int get total => present + absent + late + excused;

  /// Présences effectives (présent + retard).
  int get attended => present + late;

  /// Taux de présence effectif entre 0 et 1.
  double get rate => total == 0 ? 0 : attended / total;

  int get ratePercent => (rate * 100).round();

  int countFor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return present;
      case AttendanceStatus.absent:
        return absent;
      case AttendanceStatus.late:
        return late;
      case AttendanceStatus.excused:
        return excused;
    }
  }

  AttendanceStats merge(AttendanceStats other) => AttendanceStats(
        present: present + other.present,
        absent: absent + other.absent,
        late: late + other.late,
        excused: excused + other.excused,
      );

  @override
  String toString() =>
      'AttendanceStats(present: $present, absent: $absent, late: $late, '
      'excused: $excused)';
}

/// Résumé d'une séance de pointage (une date + une catégorie).
class AttendanceSessionSummary {
  const AttendanceSessionSummary({
    required this.sessionId,
    required this.sessionKey,
    required this.date,
    required this.category,
    required this.stats,
    required this.lastRecordedAt,
    required this.authors,
    this.isFullySynced = false,
  });

  final String sessionId;
  final String sessionKey;
  final DateTime date;
  final TeamCategory category;
  final AttendanceStats stats;
  final DateTime lastRecordedAt;

  /// Auteurs ayant pointé cette séance (généralement un seul).
  final List<String> authors;

  final bool isFullySynced;
}

/// Ligne de statistiques par joueur, utilisée par l'écran « Historique ».
class PlayerAttendanceStats {
  const PlayerAttendanceStats({
    required this.playerId,
    required this.playerName,
    required this.category,
    required this.stats,
    required this.lastSeenAt,
    this.jerseyNumber,
  });

  final String playerId;
  final String playerName;
  final TeamCategory category;
  final AttendanceStats stats;
  final DateTime? lastSeenAt;
  final int? jerseyNumber;

  double get rate => stats.rate;
}
