import 'package:hive/hive.dart';

import '../../../domain/entities/player.dart';
import '../../../domain/enums/sync_enums.dart';
import '../../../domain/enums/team_category.dart';
import '../hive_type_ids.dart';
import 'adapter_utils.dart';

/// Adapter Hive écrit à la main pour [Player].
///
/// Historique des versions :
/// - **v1** : champs d'origine, sans date de naissance ;
/// - **v2** : ajout de `birthDate` (facultatif).
///
/// La v1 reste lisible : les enregistrements déjà présents sur les téléphones
/// du staff sont migrés à la lecture, sans perte ni réinitialisation de la box.
class PlayerAdapter extends TypeAdapter<Player> {
  /// Version écrite pour les nouveaux enregistrements.
  static const int currentVersion = 2;

  @override
  final int typeId = HiveTypeIds.player;

  @override
  Player read(BinaryReader reader) {
    final version = reader.readByte();
    switch (version) {
      case 1:
        return _readV1(reader);
      case 2:
        return _readV2(reader);
      default:
        throw HiveError('Version d\'adapter Player inconnue : $version');
    }
  }

  /// v1 : champs d'origine, sans date de naissance.
  Player _readV1(BinaryReader reader) {
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
  }

  /// v2 : identique à la v1, avec `birthDate` inséré après la catégorie.
  Player _readV2(BinaryReader reader) {
    final id = reader.readString();
    final fullName = reader.readString();
    final category = TeamCategory.fromCode(reader.readString());
    final birthDate = readNullableDate(reader);
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
      birthDate: birthDate,
      jerseyNumber: jerseyNumber,
      phone: phone,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncState: syncState,
      syncedAt: syncedAt,
    );
  }

  @override
  void write(BinaryWriter writer, Player obj) {
    writer.writeByte(currentVersion);
    writer.writeString(obj.id);
    writer.writeString(obj.fullName);
    writer.writeString(obj.category.code);
    writeNullableDate(writer, obj.birthDate);
    writeNullableInt(writer, obj.jerseyNumber);
    writeNullableString(writer, obj.phone);
    writer.writeBool(obj.isActive);
    writeDate(writer, obj.createdAt);
    writeDate(writer, obj.updatedAt);
    writer.writeString(obj.syncState.code);
    writeNullableDate(writer, obj.syncedAt);
  }
}
