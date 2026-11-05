import '../entities/player.dart';
import '../enums/team_category.dart';

/// Contrat d'accès au roster local.
abstract interface class PlayerRepository {
  Stream<List<Player>> watchAll();

  Future<List<Player>> all();

  Future<List<Player>> byCategory(TeamCategory category);

  Future<List<Player>> activeByCategory(TeamCategory category);

  Future<void> upsert(Player player);

  Future<void> upsertAll(List<Player> players);

  Future<void> archive(String playerId);
}
