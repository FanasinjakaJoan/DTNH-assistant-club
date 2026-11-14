import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/auth/auth_token_source.dart';
import '../data/local/dao/attendance_dao.dart';
import '../data/local/dao/player_dao.dart';
import '../data/local/dao/sync_queue_dao.dart';
import '../data/local/dao/transaction_dao.dart';
import '../data/local/local_database.dart';
import '../data/remote/apps_script_client.dart';
import '../data/repositories/attendance_repository_impl.dart';
import '../data/repositories/player_repository_impl.dart';
import '../data/repositories/settings_repository_impl.dart';
import '../data/repositories/sync_queue_repository_impl.dart';
import '../data/repositories/transaction_repository_impl.dart';
import '../domain/entities/attendance_entry.dart';
import '../domain/entities/financial_transaction.dart';
import '../domain/entities/player.dart';
import '../domain/entities/sync_queue_item.dart';
import '../domain/enums/sync_enums.dart';
import '../domain/enums/team_category.dart';
import '../domain/repositories/attendance_repository.dart';
import '../domain/repositories/player_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/sync_queue_repository.dart';
import '../domain/repositories/transaction_repository.dart';
import '../sync/sync_engine.dart';

/// Base locale ouverte au démarrage (`bootstrap()` fait l'override).
final localDatabaseProvider = Provider<LocalDatabase>(
  (ref) => throw UnimplementedError(
    'localDatabaseProvider doit être surchargé dans bootstrap().',
  ),
);

final uuidProvider = Provider<Uuid>((ref) => const Uuid());

// ---------------------------------------------------------------------------
// DAO (accès bas niveau)
// ---------------------------------------------------------------------------

final attendanceDaoProvider = Provider<AttendanceDao>(
  (ref) => AttendanceDao(ref.watch(localDatabaseProvider)),
);

final transactionDaoProvider = Provider<TransactionDao>(
  (ref) => TransactionDao(ref.watch(localDatabaseProvider)),
);

final playerDaoProvider = Provider<PlayerDao>(
  (ref) => PlayerDao(ref.watch(localDatabaseProvider)),
);

final syncQueueDaoProvider = Provider<SyncQueueDao>(
  (ref) => SyncQueueDao(ref.watch(localDatabaseProvider)),
);

// ---------------------------------------------------------------------------
// Repositories
// ---------------------------------------------------------------------------

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(
    ref.watch(localDatabaseProvider).settingsBox,
  ),
);

final syncQueueRepositoryProvider = Provider<SyncQueueRepository>(
  (ref) => SyncQueueRepositoryImpl(
    dao: ref.watch(syncQueueDaoProvider),
    uuid: ref.watch(uuidProvider),
  ),
);

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepositoryImpl(
    dao: ref.watch(attendanceDaoProvider),
    queue: ref.watch(syncQueueRepositoryProvider),
    uuid: ref.watch(uuidProvider),
  ),
);

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepositoryImpl(
    dao: ref.watch(transactionDaoProvider),
    queue: ref.watch(syncQueueRepositoryProvider),
  ),
);

final playerRepositoryProvider = Provider<PlayerRepository>(
  (ref) => PlayerRepositoryImpl(
    dao: ref.watch(playerDaoProvider),
    queue: ref.watch(syncQueueRepositoryProvider),
  ),
);

// ---------------------------------------------------------------------------
// Réseau / synchronisation
// ---------------------------------------------------------------------------

/// Fournisseur du jeton de session Google : un seul point d'injection pour
/// tout le transport (surchargeable dans les tests).
final authTokenSourceProvider =
    Provider<AuthTokenSource>((ref) => const AuthTokenSource());

final appsScriptClientProvider = Provider<AppsScriptClient>((ref) {
  final client = AppsScriptClient(tokens: ref.watch(authTokenSourceProvider));
  ref.onDispose(client.dispose);
  return client;
});

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(
    queue: ref.watch(syncQueueRepositoryProvider),
    client: ref.watch(appsScriptClientProvider),
    settings: ref.watch(settingsRepositoryProvider),
    uuid: ref.watch(uuidProvider),
  ),
);

// ---------------------------------------------------------------------------
// Flux réactifs (source de vérité pour l'UI)
// ---------------------------------------------------------------------------

final attendanceEntriesProvider = StreamProvider<List<AttendanceEntry>>(
  (ref) => ref.watch(attendanceRepositoryProvider).watchEntries(),
);

final transactionsProvider = StreamProvider<List<FinancialTransaction>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchAll(),
);

final playersStreamProvider = StreamProvider<List<Player>>(
  (ref) => ref.watch(playerRepositoryProvider).watchAll(),
);

final syncQueueItemsProvider = StreamProvider<List<SyncQueueItem>>(
  (ref) => ref.watch(syncQueueRepositoryProvider).watchAll(),
);

/// Compteurs de la file, dérivés du flux (pas de polling).
final syncCountersProvider = Provider<SyncQueueCounters>((ref) {
  final items = ref.watch(syncQueueItemsProvider).valueOrNull ??
      const <SyncQueueItem>[];
  var pending = 0;
  var error = 0;
  var synced = 0;
  for (final item in items) {
    if (item.status == SyncState.pending) {
      pending++;
    } else if (item.status == SyncState.synced) {
      synced++;
    } else {
      error++;
    }
  }
  return SyncQueueCounters(pending: pending, error: error, synced: synced);
});

/// Joueurs actifs d'une catégorie (utilisé par le pointage).
final playersByCategoryProvider =
    Provider.family<List<Player>, TeamCategory>((ref, category) {
  final players =
      ref.watch(playersStreamProvider).valueOrNull ?? const <Player>[];
  return players
      .where((p) => p.category == category && p.isActive)
      .toList();
});
