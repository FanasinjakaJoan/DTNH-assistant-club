import '../../../domain/entities/player.dart';
import '../../../domain/enums/team_category.dart';
import '../local_database.dart';

/// Accès bas niveau au roster (box Hive `players_v1`).
class PlayerDao {
  PlayerDao(this._db);

  final LocalDatabase _db;

  List<Player> getAll() {
    final players = _db.playerBox.values.toList();
    players.sort(_byCategoryThenJersey);
    return players;
  }

  List<Player> byCategory(TeamCategory category, {bool includeArchived = false}) {
    return getAll()
        .where((p) =>
            p.category == category && (includeArchived || p.isActive))
        .toList();
  }

  Player? byId(String id) => _db.playerBox.get(id);

  Future<void> put(Player player) async {
    await _db.playerBox.put(player.id, player);
    _db.notify(DbStore.players);
  }

  Future<void> putAll(List<Player> players) async {
    if (players.isEmpty) return;
    await _db.playerBox.putAll({for (final p in players) p.id: p});
    _db.notify(DbStore.players);
  }

  Future<void> deleteById(String id) async {
    await _db.playerBox.delete(id);
    _db.notify(DbStore.players);
  }

  Stream<List<Player>> watchAll() async* {
    yield getAll();
    await for (final store in _db.changes) {
      if (store == DbStore.players) yield getAll();
    }
  }

  static int _byCategoryThenJersey(Player a, Player b) {
    final byCategory = a.category.index.compareTo(b.category.index);
    if (byCategory != 0) return byCategory;
    final aNum = a.jerseyNumber ?? 999;
    final bNum = b.jerseyNumber ?? 999;
    final byJersey = aNum.compareTo(bNum);
    if (byJersey != 0) return byJersey;
    return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
  }
}
