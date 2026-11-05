import 'package:uuid/uuid.dart';

import '../../domain/entities/player.dart';
import '../../domain/enums/sync_enums.dart';
import '../../domain/enums/team_category.dart';
import '../../domain/repositories/player_repository.dart';

/// Roster de démonstration (noms malgaches, 4 catégories).
///
/// Utile pour tester l'écran de pointage sur un téléphone neuf avant que le
/// secrétariat n'ait saisi les licences. Idempotent : n'écrase rien et ne
/// duplique pas les joueurs déjà présents.
class DemoSeed {
  const DemoSeed(this._repository);

  final PlayerRepository _repository;

  static const Map<TeamCategory, List<(String, int)>> roster = {
    TeamCategory.u12: [
      ('Rakoto Andrianina', 4),
      ('Rasoa Miora', 5),
      ('Randriamalala Toky', 6),
      ('Ravelomanana Feno', 7),
      ('Andrianjaka Soa', 8),
      ('Rafanomezantsoa Avotra', 9),
      ('Rakotondrabe Tiana', 10),
      ('Razafindrakoto Hery', 11),
    ],
    TeamCategory.u14u15: [
      ('Rakotomalala Nomena', 3),
      ('Andriantsitohaina Mamy', 4),
      ('Rasolofonirina Sitraka', 5),
      ('Ranaivoson Tahiry', 6),
      ('Rajaonarison Fandresena', 7),
      ('Rakotonirina Aina', 8),
      ('Ramaroson Fiaro', 9),
      ('Rasoanaivo Andy', 10),
      ('Randrianasolo Mihaja', 11),
      ('Rakotoarisoa Ny Aina', 12),
    ],
    TeamCategory.u16: [
      ('Rakotobe Fandresena', 3),
      ('Andriamihaja Tsiory', 4),
      ('Razafimahatratra Lova', 5),
      ('Rabemananjara Finoana', 6),
      ('Rakotozafy Santatra', 7),
      ('Rasoamiaramanana Miora', 8),
      ('Randriamalala Tafita', 9),
      ('Raveloson Ando', 10),
      ('Rakotonandrasana Herinjaka', 11),
      ('Randrianarisoa Antsa', 12),
    ],
    TeamCategory.u17u18: [
      ('Rakotondrainibe Tojo', 3),
      ('Andriambololona Rado', 4),
      ('Rasolonirina Manda', 5),
      ('Rafanomezana Hasina', 6),
      ('Randriamanantena Faniry', 7),
      ('Rakotovao Tsihoarana', 8),
      ('Razafindramboa Nantenaina', 9),
      ('Rasoarimalala Faneva', 10),
      ('Rakotoarivelo Miora', 11),
      ('Andrianarison Tsiry', 12),
    ],
  };

  /// Insère le roster manquant. Retourne le nombre de joueurs créés.
  Future<int> seedRosterIfEmpty() async {
    final existing = await _repository.all();
    if (existing.isNotEmpty) return 0;

    final now = DateTime.now();
    const uuid = Uuid();
    final players = <Player>[];
    roster.forEach((category, entries) {
      for (final entry in entries) {
        players.add(
          Player(
            id: uuid.v4(),
            fullName: entry.$1,
            category: category,
            jerseyNumber: entry.$2,
            createdAt: now,
            updatedAt: now,
            syncState: SyncState.pending,
          ),
        );
      }
    });

    await _repository.upsertAll(players);
    return players.length;
  }

  /// Ajoute un joueur manuellement (écran « Gérer l'effectif »).
  Future<void> addPlayer({
    required String fullName,
    required TeamCategory category,
    int? jerseyNumber,
    String? phone,
  }) async {
    final now = DateTime.now();
    await _repository.upsert(
      Player(
        id: const Uuid().v4(),
        fullName: fullName.trim(),
        category: category,
        jerseyNumber: jerseyNumber,
        phone: phone?.trim(),
        createdAt: now,
        updatedAt: now,
        syncState: SyncState.pending,
      ),
    );
  }
}
