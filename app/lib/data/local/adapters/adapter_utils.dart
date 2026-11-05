import 'package:hive/hive.dart';

/// Version du schéma sérialisé, écrite en tête de chaque enregistrement.
///
/// Permet une migration « record par record » : si un futur adapter ajoute un
/// champ, il incrémente la version et gère les deux branches en lecture, sans
/// perdre les données déjà présentes sur les téléphones du staff.
const int kAdapterVersion = 1;

void writeNullableString(BinaryWriter writer, String? value) {
  if (value == null) {
    writer.writeBool(false);
  } else {
    writer.writeBool(true);
    writer.writeString(value);
  }
}

String? readNullableString(BinaryReader reader) =>
    reader.readBool() ? reader.readString() : null;

void writeNullableInt(BinaryWriter writer, int? value) {
  if (value == null) {
    writer.writeBool(false);
  } else {
    writer.writeBool(true);
    writer.writeInt(value);
  }
}

int? readNullableInt(BinaryReader reader) =>
    reader.readBool() ? reader.readInt() : null;

void writeDate(BinaryWriter writer, DateTime value) =>
    writer.writeInt(value.millisecondsSinceEpoch);

DateTime readDate(BinaryReader reader) =>
    DateTime.fromMillisecondsSinceEpoch(reader.readInt());

void writeNullableDate(BinaryWriter writer, DateTime? value) {
  if (value == null) {
    writer.writeBool(false);
  } else {
    writer.writeBool(true);
    writer.writeInt(value.millisecondsSinceEpoch);
  }
}

DateTime? readNullableDate(BinaryReader reader) => reader.readBool()
    ? DateTime.fromMillisecondsSinceEpoch(reader.readInt())
    : null;

/// Garde-fou de désérialisation d'enum : un index inconnu ne doit jamais
/// faire planter l'application (données d'une version antérieure).
T enumAt<T>(List<T> values, int index, T fallback) =>
    index >= 0 && index < values.length ? values[index] : fallback;
