import 'package:hive/hive.dart';

import '../../../domain/entities/player.dart';
import '../../../domain/enums/sync_enums.dart';
import '../../../domain/enums/team_category.dart';
import '../hive_type_ids.dart';
import 'adapter_utils.dart';

/// Adapter Hive écrit à la main pour [Player].
class PlayerAdapter extends TypeAdapter<Player> {
  @override
  final int typeId = HiveTypeIds.player;

  @override
  Player read(BinaryReader reader) {
    final version = reader.readByte();
    switch (version) {
      case 1:
        final id = reader.readString();
        final fullName = reader.readString();
        final category = TeamCategory.fromCode(reader.readString());
        final jerseyNumber = readNullableInt(reader);
        final phone = readNullableString(reader);
        final isActive = reader.readBool();
        final createdAt = readDate(reader);
        final updatedAt = readDate(reader);
        final syncState = SyncState.fromCode(reader.readString());
        final syncedAt = readNullableDate(reader);
        return Player(
          id: id,
          fullName: fullName,
          category: category,
          jerseyNumber: jerseyNumber,
          phone: phone,
          isActive: isActive,
          createdAt: createdAt,
          updatedAt: updatedAt,
          syncState: syncState,
          syncedAt: syncedAt,
        );
      default:
        throw HiveError('Version d\'adapter Player inconnue : $version');
    }
  }

  @override
  void write(BinaryWriter writer, Player obj) {
    writer.writeByte(kAdapterVersion);
    writer.writeString(obj.id);
    writer.writeString(obj.fullName);
    writer.writeString(obj.category.code);
    writeNullableInt(writer, obj.jerseyNumber);
    writeNullableString(writer, obj.phone);
    writer.writeBool(obj.isActive);
    writeDate(writer, obj.createdAt);
    writeDate(writer, obj.updatedAt);
    writer.writeString(obj.syncState.code);
    writeNullableDate(writer, obj.syncedAt);
  }
}
