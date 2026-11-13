import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/local/dao/sync_queue_dao.dart';
import '../data/local/local_database.dart';
import '../data/remote/apps_script_client.dart';
import '../data/repositories/settings_repository_impl.dart';
import '../data/repositories/sync_queue_repository_impl.dart';
import 'sync_engine.dart';

/// Nom de tâche Workmanager (doit rester stable entre deux versions).
const String dtnhSyncTask = 'dtnh.sync.pending';
const String dtnhSyncPeriodicTask = 'dtnh.sync.periodic';

/// Point d'entrée **isolate d'arrière-plan**.
///
/// Contraintes à respecter :
/// - pas d'accès aux providers Riverpod (isolate séparé) : on reconstruit le
///   graphe d'objets minimal à la main ;
/// - `@pragma('vm:entry-point')` obligatoire sinon tree-shaking casse l'appel ;
/// - retour `true` = tâche réussie, `false` = Workmanager retentera.
@pragma('vm:entry-point')
void syncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    LocalDatabase? db;
    try {
      db = await LocalDatabase.open();
      final settingsRepository = SettingsRepositoryImpl(db.settingsBox);
      // Rien à faire tant qu'aucune cible n'est complète (URL + secret) :
      // la cible Supabase est pré-configurée au build, Apps Script doit être
      // renseigné à la main dans les réglages.
      if (!settingsRepository.current.hasSyncTarget) return true;

      final queueRepository =
          SyncQueueRepositoryImpl(dao: SyncQueueDao(db));
      final client = AppsScriptClient();
      final engine = SyncEngine(
        queue: queueRepository,
        client: client,
        settings: settingsRepository,
      );

      final report = await engine.drain(maxBatches: 5);
      client.dispose();
      // Retour `false` si des éléments échouent encore : Workmanager
      // replanifiera la tâche avec son propre backoff.
      return report.remaining == 0 || report.succeeded > 0;
    } catch (_) {
      return false;
    }
  });
}

/// Enregistre les tâches périodiques (Android WorkManager / iOS BGTask).
///
/// 15 minutes est la fréquence minimale autorisée par Android.
Future<void> registerBackgroundSync({bool periodic = true}) async {
  await Workmanager().initialize(syncCallbackDispatcher);
  if (!periodic) return;

  await Workmanager().registerPeriodicTask(
    'dtnh-sync-periodic',
    dtnhSyncPeriodicTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

/// Demande un passage immédiat en arrière-plan (bouton « Sync en fond »).
Future<void> requestOneOffSync() async {
  await Workmanager().registerOneOffTask(
    'dtnh-sync-now-${DateTime.now().millisecondsSinceEpoch}',
    dtnhSyncTask,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

Future<void> cancelBackgroundSync() async {
  await Workmanager().cancelByUniqueName('dtnh-sync-periodic');
}
