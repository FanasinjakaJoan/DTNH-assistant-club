/// Statut de synchronisation d'une donnée locale.
///
/// Source de vérité : `SyncQueueItem.status`. Les entités métier en conservent
/// une copie dénormalisée (`syncState`) uniquement pour l'affichage, ce qui
/// évite une jointure en mémoire à chaque rendu de liste.
enum SyncState {
  pending(code: 'PENDING', label: 'En attente'),
  synced(code: 'SYNCED', label: 'Synchronisé'),
  error(code: 'ERROR', label: 'Erreur');

  const SyncState({required this.code, required this.label});

  final String code;
  final String label;

  static SyncState fromCode(String? code) {
    switch (code?.toUpperCase()) {
      case 'SYNCED':
        return SyncState.synced;
      case 'ERROR':
        return SyncState.error;
      default:
        return SyncState.pending;
    }
  }
}

/// Nature de l'opération à rejouer côté Google Sheets.
enum SyncOperation {
  upsert(code: 'upsert'),
  delete(code: 'delete');

  const SyncOperation({required this.code});

  final String code;

  static SyncOperation fromCode(String? code) =>
      code?.toLowerCase() == 'delete'
          ? SyncOperation.delete
          : SyncOperation.upsert;
}

/// Types d'entités synchronisables et onglet cible correspondant.
enum SyncEntityType {
  attendance(code: 'attendance', sheetName: 'Présences'),
  transaction(code: 'transaction', sheetName: 'Transactions'),
  player(code: 'player', sheetName: 'Joueurs');

  const SyncEntityType({required this.code, required this.sheetName});

  final String code;

  /// Nom de l'onglet Google Sheets cible (doit correspondre au schéma
  /// déclaré dans `apps-script/Code.gs`).
  final String sheetName;

  static SyncEntityType? tryParse(String? code) {
    if (code == null) return null;
    for (final type in SyncEntityType.values) {
      if (type.code == code || type.name == code) return type;
    }
    return null;
  }
}
