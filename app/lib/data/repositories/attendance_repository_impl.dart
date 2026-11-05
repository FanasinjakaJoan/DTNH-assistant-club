import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/date_x.dart';
import '../../domain/entities/attendance_entry.dart';
import '../../domain/entities/attendance_stats.dart';
import '../../domain/entities/player.dart';
import '../../domain/enums/attendance_status.dart';
import '../../domain/enums/sync_enums.dart';
import '../../domain/enums/team_category.dart';
import '../../domain/repositories/attendance_repository.dart';
import '../../domain/repositories/sync_queue_repository.dart';
import '../local/dao/attendance_dao.dart';
import '../remote/sync_payloads.dart';

/// Implémentation locale des présences : écriture Hive + mise en file.
///
/// Invariant : **une écriture métier n'est jamais perdue**. L'entité est
/// persistée puis mise en file ; si la mise en file échoue, l'entité reste en
/// `pending` et sera reprise par le prochain passage du moteur.
class AttendanceRepositoryImpl implements AttendanceRepository {
  AttendanceRepositoryImpl({
    required AttendanceDao dao,
    required SyncQueueRepository queue,
    Uuid uuid = const Uuid(),
  })  : _dao = dao,
        _queue = queue,
        _uuid = uuid;

  final AttendanceDao _dao;
  final SyncQueueRepository _queue;
  final Uuid _uuid;

  @override
  Stream<List<AttendanceEntry>> watchEntries() => _dao.watchAll();

  @override
  Future<List<AttendanceEntry>> entriesForSession({
    required TeamCategory category,
    required DateTime date,
  }) async =>
      _dao.forDay(category: category, date: date);

  @override
  Future<void> saveSession({
    required TeamCategory category,
    required DateTime date,
    required List<Player> players,
    required Map<String, AttendanceStatus> statuses,
    required String authorId,
    required String authorName,
  }) async {
    final existing = _dao.forDay(category: category, date: date);
    final sessionId =
        existing.isNotEmpty ? existing.first.sessionId : _uuid.v4();
    final now = DateTime.now();

    final entries = <AttendanceEntry>[];
    for (final player in players) {
      final status = statuses[player.id];
      if (status == null) continue;
      final current = existing.firstWhereOrNull(
        (entry) => entry.playerId == player.id,
      );
      entries.add(
        AttendanceEntry(
          id: current?.id ?? _uuid.v4(),
          sessionId: sessionId,
          sessionDate: date.dateOnly,
          recordedAt: now,
          category: category,
          playerId: player.id,
          playerName: player.fullName,
          jerseyNumber: player.jerseyNumber,
          status: status,
          authorId: authorId,
          authorName: authorName,
          syncState: SyncState.pending,
          updatedAt: now,
        ),
      );
    }

    // Joueurs décochés lors d'une reprise : on supprime la ligne locale.
    final pointedIds = entries.map((e) => e.playerId).toSet();
    final stale = existing
        .where((entry) => !pointedIds.contains(entry.playerId))
        .map((entry) => entry.id)
        .toList();

    if (stale.isNotEmpty) await _dao.deleteByIds(stale);
    await _dao.putAll(entries);

    for (final entry in entries) {
      await _queue.enqueue(
        entityType: SyncEntityType.attendance,
        entityId: entry.id,
        payload: SyncPayloads.attendance(entry),
      );
    }
  }

  @override
  Future<List<AttendanceSessionSummary>> recentSessions({
    TeamCategory? category,
    int limit = 40,
  }) async {
    final source = category == null ? _dao.getAll() : _dao.byCategory(category);
    final groups = groupBy(source, (AttendanceEntry entry) => entry.sessionKey);

    final summaries = groups.entries.map((entry) {
      final rows = entry.value;
      return AttendanceSessionSummary(
        sessionId: rows.first.sessionId,
        sessionKey: entry.key,
        date: rows.first.sessionDate,
        category: rows.first.category,
        stats: _statsOf(rows),
        lastRecordedAt: rows
            .map((row) => row.recordedAt)
            .reduce((a, b) => a.isAfter(b) ? a : b),
        authors: rows.map((row) => row.authorName).toSet().toList(),
        isFullySynced: rows.every((row) => row.isSynced),
      );
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return summaries.take(limit).toList();
  }

  @override
  Future<List<AttendanceEntry>> entriesOfPlayer(String playerId) async =>
      _dao.byPlayer(playerId);

  @override
  Future<AttendanceStats> statsForCategory(TeamCategory category) async =>
      _statsOf(_dao.byCategory(category));

  @override
  Future<List<PlayerAttendanceStats>> playerStats({
    TeamCategory? category,
    DateTime? from,
    DateTime? to,
  }) async {
    final source = (category == null ? _dao.getAll() : _dao.byCategory(category))
        .where((entry) {
      if (from != null && entry.sessionDate.isBefore(from.dateOnly)) {
        return false;
      }
      if (to != null && entry.sessionDate.isAfter(to.dateOnly)) {
        return false;
      }
      return true;
    }).toList();

    final byPlayer =
        groupBy(source, (AttendanceEntry entry) => entry.playerId);

    final result = byPlayer.entries.map((entry) {
      final rows = entry.value;
      rows.sort((a, b) => b.sessionDate.compareTo(a.sessionDate));
      final present = rows.first;
      return PlayerAttendanceStats(
        playerId: entry.key,
        playerName: present.playerName,
        category: present.category,
        jerseyNumber: present.jerseyNumber,
        stats: _statsOf(rows),
        lastSeenAt: rows
            .where((row) => row.status.countsAsPresent)
            .map((row) => row.sessionDate)
            .firstOrNull,
      );
    }).toList()
      ..sort((a, b) => b.stats.rate.compareTo(a.stats.rate));

    return result;
  }

  AttendanceStats _statsOf(Iterable<AttendanceEntry> entries) {
    var present = 0;
    var absent = 0;
    var lateCount = 0;
    var excused = 0;
    for (final entry in entries) {
      if (entry.status == AttendanceStatus.present) {
        present++;
      } else if (entry.status == AttendanceStatus.absent) {
        absent++;
      } else if (entry.status == AttendanceStatus.retard) {
        lateCount++;
      } else {
        excused++;
      }
    }
    return AttendanceStats(
      present: present,
      absent: absent,
      lateCount: lateCount,
      excused: excused,
    );
  }
}
