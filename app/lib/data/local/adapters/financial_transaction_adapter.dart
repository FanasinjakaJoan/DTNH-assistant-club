import 'package:hive/hive.dart';

import '../../../domain/entities/financial_transaction.dart';
import '../../../domain/enums/sync_enums.dart';
import '../../../domain/enums/transaction_enums.dart';
import '../hive_type_ids.dart';
import 'adapter_utils.dart';

/// Adapter Hive écrit à la main pour [FinancialTransaction].
class FinancialTransactionAdapter extends TypeAdapter<FinancialTransaction> {
  @override
  final int typeId = HiveTypeIds.financialTransaction;

  @override
  FinancialTransaction read(BinaryReader reader) {
    final version = reader.readByte();
    switch (version) {
      case 1:
        final id = reader.readString();
        final date = readDate(reader);
        final flow = TransactionFlow.fromCode(reader.readString());
        final category = TransactionCategory.fromCode(reader.readString());
        final amount = reader.readInt();
        final paymentMethod = PaymentMethod.fromCode(reader.readString());
        final details = readNullableString(reader);
        final playerName = readNullableString(reader);
        final staffName = readNullableString(reader);
        final eventName = readNullableString(reader);
        final periodMonth = readNullableString(reader);
        final authorId = reader.readString();
        final authorName = reader.readString();
        final createdAt = readDate(reader);
        final updatedAt = readDate(reader);
        final syncState = SyncState.fromCode(reader.readString());
        final syncedAt = readNullableDate(reader);
        return FinancialTransaction(
          id: id,
          date: date,
          flow: flow,
          category: category,
          amount: amount,
          paymentMethod: paymentMethod,
          details: details,
          playerName: playerName,
          staffName: staffName,
          eventName: eventName,
          periodMonth: periodMonth,
          authorId: authorId,
          authorName: authorName,
          createdAt: createdAt,
          updatedAt: updatedAt,
          syncState: syncState,
          syncedAt: syncedAt,
        );
      default:
        throw HiveError(
          'Version d\'adapter FinancialTransaction inconnue : $version',
        );
    }
  }

  @override
  void write(BinaryWriter writer, FinancialTransaction obj) {
    writer.writeByte(kAdapterVersion);
    writer.writeString(obj.id);
    writeDate(writer, obj.date);
    writer.writeString(obj.flow.code);
    writer.writeString(obj.category.code);
    writer.writeInt(obj.amount);
    writer.writeString(obj.paymentMethod.code);
    writeNullableString(writer, obj.details);
    writeNullableString(writer, obj.playerName);
    writeNullableString(writer, obj.staffName);
    writeNullableString(writer, obj.eventName);
    writeNullableString(writer, obj.periodMonth);
    writer.writeString(obj.authorId);
    writer.writeString(obj.authorName);
    writeDate(writer, obj.createdAt);
    writeDate(writer, obj.updatedAt);
    writer.writeString(obj.syncState.code);
    writeNullableDate(writer, obj.syncedAt);
  }
}
