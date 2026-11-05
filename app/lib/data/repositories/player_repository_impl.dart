import '../../domain/entities/player.dart';
import '../../domain/enums/sync_enums.dart';
import '../../domain/enums/team_category.dart';
import '../../domain/repositories/player_repository.dart';
import '../../domain/repositories/sync_queue_repository.dart';
import '../local/dao/player_dao.dart';
import '../remote/sync_payloads.dart';

/// Implémentation locale du roster.
class PlayerRepositoryImpl implements PlayerRepository {
  PlayerRepositoryImpl({
    required PlayerDao dao,
    required SyncQueueRepository queue,
  })  : _dao = dao,
        _queue = queue;

  final PlayerDao _dao;
  final SyncQueueRepository _queue;

  @override
  Stream<List<Player>> watchAll() => _dao.watchAll();

  @override
  Future<List<Player>> all() async => _dao.getAll();

  @override
  Future<List<Player>> byCategory(TeamCategory category) async =>
      _dao.byCategory(category, includeArchived: true);

  @override
  Future<List<Player>> activeByCategory(TeamCategory category) async =>
      _dao.byCategory(category);

  @override
  Future<void> upsert(Player player) async {
    final now = DateTime.now();
    final toStore = player.copyWith(
      syncState: SyncState.pending,
      clearSyncedAt: true,
      updatedAt: now,
    );
    await _dao.put(toStore);
    await _queue.enqueue(
      entityType: SyncEntityType.player,
      entityId: toStore.id,
      payload: SyncPayloads.player(toStore),
    );
  }

  @override
  Future<void> upsertAll(List<Player> players) async {
    for (final player in players) {
      await upsert(player);
    }
  }

  @override
  Future<void> archive(String playerId) async {
    final player = _dao.byId(playerId);
    if (player == null) return;
    await upsert(
      player.copyWith(isActive: false, updatedAt: DateTime.now()),
    );
  }
}
