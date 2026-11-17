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
    this.birthDate,
    this.jerseyNumber,
    this.phone,
    this.isActive = true,
    this.syncState = SyncState.pending,
    this.syncedAt,
  });

  final String id;
  final String fullName;
  final TeamCategory category;

  /// Date de naissance (minuit local), `null` tant qu'elle n'est pas saisie.
  ///
  /// Elle sert à calculer l'âge affiché et à proposer la bonne catégorie, sans
  /// jamais l'imposer : beaucoup de clubs alignent un joueur surclassé.
  final DateTime? birthDate;

  final int? jerseyNumber;
  final String? phone;

  /// Un joueur inactif reste dans l'historique mais n'apparaît plus au pointage.
  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncState syncState;
  final DateTime? syncedAt;

  /// Âge révolu au jour [on] (par défaut : maintenant), `null` sans date de
  /// naissance.
  ///
  /// Le calcul compare les composantes (année, mois, jour) plutôt qu'une
  /// différence de millisecondes : le résultat est stable d'une exécution à
  /// l'autre et ne dépend pas de l'heure de la journée. Un joueur né un
  /// 29 février « prend un an » le 1er mars les années non bissextiles.
  int? ageAt(DateTime on) {
    final birth = birthDate;
    if (birth == null) return null;
    var age = on.year - birth.year;
    final beforeBirthday = on.month < birth.month ||
        (on.month == birth.month && on.day < birth.day);
    if (beforeBirthday) age--;
    return age < 0 ? null : age;
  }

  /// Âge révolu aujourd'hui, `null` sans date de naissance.
  int? get age => ageAt(DateTime.now());

  /// Catégorie suggérée par l'âge, `null` si la date manque ou sort du barème.
  TeamCategory? get suggestedCategory {
    final value = age;
    return value == null ? null : TeamCategory.forAge(value);
  }

  /// `2012-04-17`, `null` sans date de naissance.
  String? get birthDateYmd {
    final birth = birthDate;
    if (birth == null) return null;
    return '${birth.year.toString().padLeft(4, '0')}-'
        '${birth.month.toString().padLeft(2, '0')}-'
        '${birth.day.toString().padLeft(2, '0')}';
  }

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
    DateTime? birthDate,
    bool clearBirthDate = false,
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
      birthDate: clearBirthDate ? null : (birthDate ?? this.birthDate),
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
