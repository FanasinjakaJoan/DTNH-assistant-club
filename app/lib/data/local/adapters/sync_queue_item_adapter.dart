import 'dart:convert';

import 'package:hive/hive.dart';

import '../../../domain/entities/sync_queue_item.dart';
import '../../../domain/enums/sync_enums.dart';
import '../hive_type_ids.dart';
import 'adapter_utils.dart';

/// Adapter Hive de la file d'attente.
///
/// La charge utile JSON est stockée **sous forme de chaîne** : Hive ne sait pas
/// sérialiser proprement des `Map<String, dynamic>` imbriquées, et conserver la
/// chaîne garantit que le payload renvoyé au Sheet est exactement celui généré
/// au moment du pointage.
class SyncQueueItemAdapter extends TypeAdapter<SyncQueueItem> {
  @override
  final int typeId = HiveTypeIds.syncQueueItem;

  @override
  SyncQueueItem read(BinaryReader reader) {
    final version = reader.readByte();
    switch (version) {
      case 1:
        final id = reader.readString();
        final entityType =
            SyncEntityType.tryParse(reader.readString()) ??
                SyncEntityType.attendance;
        final entityId = reader.readString();
        final operation = SyncOperation.fromCode(reader.readString());
        final payloadJson = reader.readString();
        final status = SyncState.fromCode(reader.readString());
        final attempts = reader.readInt();
        final lastError = readNullableString(reader);
        final createdAt = readDate(reader);
        final updatedAt = readDate(reader);
        final syncedAt = readNullableDate(reader);
        final batchId = readNullableString(reader);

        Map<String, dynamic> payload;
        try {
          final decoded = jsonDecode(payloadJson);
          payload = decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : <String, dynamic>{};
        } on FormatException {
          payload = <String, dynamic>{};
        }

        return SyncQueueItem(
          id: id,
          entityType: entityType,
          entityId: entityId,
          operation: operation,
          payload: payload,
          status: status,
          attempts: attempts,
          lastError: lastError,
          createdAt: createdAt,
          updatedAt: updatedAt,
          syncedAt: syncedAt,
          batchId: batchId,
        );
      default:
        throw HiveError('Version d\'adapter SyncQueueItem inconnue : $version');
    }
  }

  @override
  void write(BinaryWriter writer, SyncQueueItem obj) {
    writer.writeByte(kAdapterVersion);
    writer.writeString(obj.id);
    writer.writeString(obj.entityType.code);
    writer.writeString(obj.entityId);
    writer.writeString(obj.operation.code);
    writer.writeString(jsonEncode(obj.payload));
    writer.writeString(obj.status.code);
    writer.writeInt(obj.attempts);
    writeNullableString(writer, obj.lastError);
    writeDate(writer, obj.createdAt);
    writeDate(writer, obj.updatedAt);
    writeNullableDate(writer, obj.syncedAt);
    writeNullableString(writer, obj.batchId);
  }
}
