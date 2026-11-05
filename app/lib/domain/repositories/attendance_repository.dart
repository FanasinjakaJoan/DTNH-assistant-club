import '../entities/attendance_entry.dart';
import '../entities/attendance_stats.dart';
import '../entities/player.dart';
import '../enums/attendance_status.dart';
import '../enums/team_category.dart';

/// Contrat d'accès aux présences (implémenté sur Hive, remplaçable par Drift).
abstract interface class AttendanceRepository {
  /// Toutes les lignes, triées de la plus récente à la plus ancienne.
  Stream<List<AttendanceEntry>> watchEntries();

  /// Pointage déjà enregistré pour une catégorie et une date.
  Future<List<AttendanceEntry>> entriesForSession({
    required TeamCategory category,
    required DateTime date,
  });

  /// Enregistre (ou met à jour) le pointage complet d'une séance.
  ///
  /// [statuses] associe `playerId -> statut`. Les joueurs absents de la map
  /// sont considérés comme non pointés et ne génèrent aucune ligne.
  Future<void> saveSession({
    required TeamCategory category,
    required DateTime date,
    required List<Player> players,
    required Map<String, AttendanceStatus> statuses,
    required String authorId,
    required String authorName,
  });

  Future<List<AttendanceSessionSummary>> recentSessions({
    TeamCategory? category,
    int limit = 40,
  });

  Future<List<AttendanceEntry>> entriesOfPlayer(String playerId);

  Future<AttendanceStats> statsForCategory(TeamCategory category);

  Future<List<PlayerAttendanceStats>> playerStats({
    TeamCategory? category,
    DateTime? from,
    DateTime? to,
  });
}
