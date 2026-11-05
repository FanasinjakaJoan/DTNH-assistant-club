import '../enums/sync_enums.dart';
import '../enums/team_category.dart';

/// Fiche joueur du roster local (utilisée par l'écran de pointage).
///
/// Le roster est géré hors-ligne : le staff peut ajouter un joueur au bord du
/// terrain, il sera synchronisé vers l'onglet `Joueurs` à la prochaine connexion.
class Player {
  const Player({
    required this.id,
    required this.fullName,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.jerseyNumber,
    this.phone,
    this.isActive = true,
    this.syncState = SyncState.pending,
    this.syncedAt,
  });

  final String id;
  final String fullName;
  final TeamCategory category;
  final int? jerseyNumber;
  final String? phone;

  /// Un joueur inactif reste dans l'historique mais n'apparaît plus au pointage.
  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncState syncState;
  final DateTime? syncedAt;

  /// Initiales pour l'avatar (ex : « Rasoa Miora » -> « RM »).
  String get initials {
    final words = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return (words.first.characters.first + words.last.characters.first)
        .toUpperCase();
  }

  Player copyWith({
    String? fullName,
    TeamCategory? category,
    int? jerseyNumber,
    bool clearJerseyNumber = false,
    String? phone,
    bool? isActive,
    DateTime? updatedAt,
    SyncState? syncState,
    DateTime? syncedAt,
    bool clearSyncedAt = false,
  }) {
    return Player(
      id: id,
      fullName: fullName ?? this.fullName,
      category: category ?? this.category,
      jerseyNumber:
          clearJerseyNumber ? null : (jerseyNumber ?? this.jerseyNumber),
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncState: syncState ?? this.syncState,
      syncedAt: clearSyncedAt ? null : (syncedAt ?? this.syncedAt),
    );
  }

  @override
  String toString() => 'Player($fullName, ${category.code})';
}

/// Extension utilitaire sans dépendance Flutter (équivalent de `characters`).
extension on String {
  Iterable<String> get characters => split('');
}
