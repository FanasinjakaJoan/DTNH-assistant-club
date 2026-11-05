import '../../core/utils/date_x.dart';
import '../enums/attendance_status.dart';
import '../enums/sync_enums.dart';
import '../enums/team_category.dart';

/// Une ligne de présence : **un joueur** pour **une séance** d'une catégorie.
///
/// Le couple ([sessionId], [playerId]) est unique : re-pointer la même séance
/// met à jour la ligne existante (même `id`) au lieu de créer un doublon dans
/// le Google Sheet.
class AttendanceEntry {
  const AttendanceEntry({
    required this.id,
    required this.sessionId,
    required this.sessionDate,
    required this.recordedAt,
    required this.category,
    required this.playerId,
    required this.playerName,
    required this.status,
    required this.authorId,
    required this.authorName,
    required this.updatedAt,
    this.jerseyNumber,
    this.note,
    this.syncState = SyncState.pending,
    this.syncedAt,
  });

  /// UUID v4 — clé primaire locale **et** clé d'idempotence côté Sheet.
  final String id;

  /// UUID de la séance de pointage (regroupe les lignes saisies ensemble).
  final String sessionId;

  /// Date de la séance (minuit local).
  final DateTime sessionDate;

  /// Horodatage exact du pointage (date + heure + minute).
  final DateTime recordedAt;

  final TeamCategory category;
  final String playerId;

  /// Nom dénormalisé : permet d'afficher l'historique même si la fiche joueur
  /// a été supprimée ou renommée, et rend le Sheet lisible sans jointure.
  final String playerName;

  final int? jerseyNumber;
  final AttendanceStatus status;

  /// Auteur du pointage (staff / coach / admin).
  final String authorId;
  final String authorName;

  final String? note;
  final SyncState syncState;
  final DateTime? syncedAt;
  final DateTime updatedAt;

  /// Clé logique d'une séance : `2026-11-05#U16`.
  String get sessionKey => '${sessionDate.ymd}#${category.code}';

  bool get isSynced => syncState == SyncState.synced;

  AttendanceEntry copyWith({
    String? id,
    String? sessionId,
    DateTime? sessionDate,
    DateTime? recordedAt,
    TeamCategory? category,
    String? playerId,
    String? playerName,
    int? jerseyNumber,
    bool clearJerseyNumber = false,
    AttendanceStatus? status,
    String? authorId,
    String? authorName,
    String? note,
    SyncState? syncState,
    DateTime? syncedAt,
    bool clearSyncedAt = false,
    DateTime? updatedAt,
  }) {
    return AttendanceEntry(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      sessionDate: sessionDate ?? this.sessionDate,
      recordedAt: recordedAt ?? this.recordedAt,
      category: category ?? this.category,
      playerId: playerId ?? this.playerId,
      playerName: playerName ?? this.playerName,
      jerseyNumber:
          clearJerseyNumber ? null : (jerseyNumber ?? this.jerseyNumber),
      status: status ?? this.status,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      note: note ?? this.note,
      syncState: syncState ?? this.syncState,
      syncedAt: clearSyncedAt ? null : (syncedAt ?? this.syncedAt),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'AttendanceEntry($sessionKey, $playerName -> ${status.code})';
}
