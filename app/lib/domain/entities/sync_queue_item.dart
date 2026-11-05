import '../enums/sync_enums.dart';

/// Élément de la file d'attente de synchronisation (outbox pattern).
///
/// Chaque écriture locale crée (ou **fusionne**) un item `PENDING`. Le moteur
/// de synchronisation ne fait que consommer cette file : si l'application est
/// tuée ou le téléphone hors-ligne pendant des jours, aucune donnée n'est
/// perdue et rien n'est envoyé deux fois.
class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    this.status = SyncState.pending,
    this.attempts = 0,
    this.lastError,
    this.syncedAt,
    this.batchId,
  });

  /// UUID de l'item de file.
  final String id;

  final SyncEntityType entityType;

  /// Identifiant de l'entité métier concernée (clé de coalescence).
  final String entityId;

  final SyncOperation operation;

  /// Charge utile JSON prête à être envoyée (champs nommés, pas de positions).
  final Map<String, dynamic> payload;

  final SyncState status;

  /// Nombre de tentatives d'envoi (backoff exponentiel plafonné).
  final int attempts;

  /// Dernier message d'erreur (technique ou renvoyé par Apps Script).
  final String? lastError;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? syncedAt;

  /// Identifiant du lot d'envoi (traçabilité côté serveur).
  final String? batchId;

  /// Onglet Google Sheets cible, dérivé du type d'entité.
  String get sheetName => entityType.sheetName;

  bool get isPending => status == SyncState.pending;

  bool get canRetry => status != SyncState.synced;

  SyncQueueItem copyWith({
    SyncEntityType? entityType,
    String? entityId,
    SyncOperation? operation,
    Map<String, dynamic>? payload,
    SyncState? status,
    int? attempts,
    String? lastError,
    bool clearLastError = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
    bool clearSyncedAt = false,
    String? batchId,
  }) {
    return SyncQueueItem(
      id: id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: clearSyncedAt ? null : (syncedAt ?? this.syncedAt),
      batchId: batchId ?? this.batchId,
    );
  }

  @override
  String toString() =>
      'SyncQueueItem(${entityType.code}/$entityId, ${status.code}, '
      'attempts: $attempts)';
}
