import 'package:hive/hive.dart';

import '../../../domain/entities/attendance_entry.dart';
import '../../../domain/enums/attendance_status.dart';
import '../../../domain/enums/sync_enums.dart';
import '../../../domain/enums/team_category.dart';
import '../hive_type_ids.dart';
import 'adapter_utils.dart';

/// Adapter Hive **écrit à la main** : pas de `build_runner`, pas de fichier
/// `.g.dart` à committer, donc un projet qui compile dès le clone.
///
/// Ordre de lecture/écriture strictement identique — c'est le seul invariant
/// à respecter lors d'une évolution du schéma (en incrémentant la version).
class AttendanceEntryAdapter extends TypeAdapter<AttendanceEntry> {
  @override
  final int typeId = HiveTypeIds.attendanceEntry;

  @override
  AttendanceEntry read(BinaryReader reader) {
    final version = reader.readByte();
    switch (version) {
      case 1:
        final id = reader.readString();
        final sessionId = reader.readString();
        final sessionDate = readDate(reader);
        final recordedAt = readDate(reader);
        final category = TeamCategory.fromCode(reader.readString());
        final playerId = reader.readString();
        final playerName = reader.readString();
        final jerseyNumber = readNullableInt(reader);
        final status = AttendanceStatus.fromCode(reader.readString());
        final authorId = reader.readString();
        final authorName = reader.readString();
        final note = readNullableString(reader);
        final syncState = SyncState.fromCode(reader.readString());
        final syncedAt = readNullableDate(reader);
        final updatedAt = readDate(reader);
        return AttendanceEntry(
          id: id,
          sessionId: sessionId,
          sessionDate: sessionDate,
          recordedAt: recordedAt,
          category: category,
          playerId: playerId,
          playerName: playerName,
          jerseyNumber: jerseyNumber,
          status: status,
          authorId: authorId,
          authorName: authorName,
          note: note,
          syncState: syncState,
          syncedAt: syncedAt,
          updatedAt: updatedAt,
        );
      default:
        throw HiveError(
          'Version d\'adapter AttendanceEntry inconnue : $version',
        );
    }
  }

  @override
  void write(BinaryWriter writer, AttendanceEntry obj) {
    writer.writeByte(kAdapterVersion);
    writer.writeString(obj.id);
    writer.writeString(obj.sessionId);
    writeDate(writer, obj.sessionDate);
    writeDate(writer, obj.recordedAt);
    writer.writeString(obj.category.code);
    writer.writeString(obj.playerId);
    writer.writeString(obj.playerName);
    writeNullableInt(writer, obj.jerseyNumber);
    writer.writeString(obj.status.code);
    writer.writeString(obj.authorId);
    writer.writeString(obj.authorName);
    writeNullableString(writer, obj.note);
    writer.writeString(obj.syncState.code);
    writeNullableDate(writer, obj.syncedAt);
    writeDate(writer, obj.updatedAt);
  }
}
