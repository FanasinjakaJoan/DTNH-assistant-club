/// Identifiants de type Hive : **ne jamais réutiliser ou réordonner** un id,
/// sinon les données locales existantes deviennent illisibles.
class HiveTypeIds {
  const HiveTypeIds._();

  static const int attendanceEntry = 1;
  static const int financialTransaction = 2;
  static const int syncQueueItem = 3;
  static const int player = 4;
}

/// Noms des boxes Hive (une box par agrégat).
class HiveBoxes {
  const HiveBoxes._();

  static const String attendance = 'attendance_entries_v1';
  static const String transactions = 'financial_transactions_v1';
  static const String players = 'players_v1';
  static const String syncQueue = 'sync_queue_v1';
  static const String settings = 'settings_v1';
}
