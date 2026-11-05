import '../../../domain/entities/attendance_entry.dart';
import '../../../domain/enums/attendance_status.dart';
import '../../../domain/enums/team_category.dart';
import '../local_database.dart';

/// Accès bas niveau aux présences (box Hive `attendance_entries_v1`).
///
/// Aucune logique métier ici : uniquement de la lecture/écriture et le tri.
class AttendanceDao {
  AttendanceDao(this._db);

  final LocalDatabase _db;

  List<AttendanceEntry> getAll() {
    final entries = _db.attendanceBox.values.toList();
    entries.sort(_byMostRecentFirst);
    return entries;
  }

  List<AttendanceEntry> bySessionId(String sessionId) =>
      getAll().where((e) => e.sessionId == sessionId).toList();

  List<AttendanceEntry> bySessionKey(String sessionKey) =>
      getAll().where((e) => e.sessionKey == sessionKey).toList();

  List<AttendanceEntry> byPlayer(String playerId) =>
      getAll().where((e) => e.playerId == playerId).toList();

  List<AttendanceEntry> byCategory(TeamCategory category) =>
      getAll().where((e) => e.category == category).toList();

  /// Pointage existant pour une catégorie et un jour donnés.
  List<AttendanceEntry> forDay({
    required TeamCategory category,
    required DateTime date,
  }) {
    return getAll()
        .where((e) =>
            e.category == category &&
            e.sessionDate.year == date.year &&
            e.sessionDate.month == date.month &&
            e.sessionDate.day == date.day)
        .toList();
  }

  Future<void> put(AttendanceEntry entry) async {
    await _db.attendanceBox.put(entry.id, entry);
    _db.notify(DbStore.attendance);
  }

  Future<void> putAll(Iterable<AttendanceEntry> entries) async {
    final map = <String, AttendanceEntry>{for (final e in entries) e.id: e};
    if (map.isEmpty) return;
    await _db.attendanceBox.putAll(map);
    _db.notify(DbStore.attendance);
  }

  Future<void> deleteByIds(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await _db.attendanceBox.deleteAll(list);
    _db.notify(DbStore.attendance);
  }

  Stream<List<AttendanceEntry>> watchAll() async* {
    yield getAll();
    await for (final store in _db.changes) {
      if (store == DbStore.attendance) yield getAll();
    }
  }

  /// Statut d'un joueur pour une séance (utilisé par l'écran de pointage).
  AttendanceStatus? statusOf({
    required String sessionId,
    required String playerId,
  }) {
    for (final entry in _db.attendanceBox.values) {
      if (entry.sessionId == sessionId && entry.playerId == playerId) {
        return entry.status;
      }
    }
    return null;
  }

  static int _byMostRecentFirst(AttendanceEntry a, AttendanceEntry b) {
    final byDate = b.sessionDate.compareTo(a.sessionDate);
    if (byDate != 0) return byDate;
    return b.recordedAt.compareTo(a.recordedAt);
  }
}
