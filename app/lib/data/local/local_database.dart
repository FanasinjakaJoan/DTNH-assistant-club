import 'dart:async';

import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../domain/entities/attendance_entry.dart';
import '../../domain/entities/financial_transaction.dart';
import '../../domain/entities/player.dart';
import '../../domain/entities/sync_queue_item.dart';
import 'adapters/attendance_entry_adapter.dart';
import 'adapters/financial_transaction_adapter.dart';
import 'adapters/player_adapter.dart';
import 'adapters/sync_queue_item_adapter.dart';
import 'hive_type_ids.dart';

/// Agrégats dont les écritures sont diffusées aux couches supérieures.
enum DbStore { attendance, transactions, players, syncQueue, settings }

/// Point d'entrée unique du stockage local.
///
/// Choisir **Hive** plutôt que Drift/Isar ici est une décision assumée :
/// - aucune dépendance native à builder (fonctionne dès le clone) ;
/// - écritures < 1 ms sur un téléphone d'entrée de gamme ;
/// - boxes typées + adapters écrits à la main => zéro `build_runner`.
///
/// Le léger déficit (pas de SQL) est compensé par un volume de données
/// plafonné (4 catégories × ~15 joueurs × 2 séances/semaine) et par des
/// agrégations faites en mémoire, hors du thread d'UI pour les gros volumes.
class LocalDatabase {
  LocalDatabase._({
    required this.attendanceBox,
    required this.transactionBox,
    required this.playerBox,
    required this.syncQueueBox,
    required this.settingsBox,
  });

  final Box<AttendanceEntry> attendanceBox;
  final Box<FinancialTransaction> transactionBox;
  final Box<Player> playerBox;
  final Box<SyncQueueItem> syncQueueBox;
  final Box<dynamic> settingsBox;

  final StreamController<DbStore> _changes =
      StreamController<DbStore>.broadcast();

  /// Flux de notifications d'écriture (consommé par les DAO pour exposer des
  /// `Stream` réactifs façon `watch()` de Drift).
  Stream<DbStore> get changes => _changes.stream;

  void notify(DbStore store) {
    if (!_changes.isClosed) _changes.add(store);
  }

  /// Enregistre les adapters une seule fois par isolate.
  ///
  /// On interroge `Hive.isAdapterRegistered` plutôt que de mémoriser un booléen
  /// statique : après un `Hive.close()` (tests, réouverture), Hive peut vider
  /// son registre d'adapters.
  static void registerAdapters() {
    if (!Hive.isAdapterRegistered(HiveTypeIds.attendanceEntry)) {
      Hive.registerAdapter(AttendanceEntryAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.financialTransaction)) {
      Hive.registerAdapter(FinancialTransactionAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.syncQueueItem)) {
      Hive.registerAdapter(SyncQueueItemAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.player)) {
      Hive.registerAdapter(PlayerAdapter());
    }
  }

  /// Ouvre (ou crée) toutes les boxes.
  ///
  /// [directory] est utilisé par les tests unitaires : `Hive.init(tempDir)`.
  /// En production on laisse Hive choisir le dossier applicatif via
  /// `initFlutter()`. Le worker d'arrière-plan appelle la même méthode.
  static Future<LocalDatabase> open({String? directory}) async {
    if (directory != null) {
      Hive.init(directory);
    } else if (!Hive.isBoxOpen(HiveBoxes.settings)) {
      await Hive.initFlutter();
    }

    registerAdapters();

    final attendanceBox =
        await Hive.openBox<AttendanceEntry>(HiveBoxes.attendance);
    final transactionBox =
        await Hive.openBox<FinancialTransaction>(HiveBoxes.transactions);
    final playerBox = await Hive.openBox<Player>(HiveBoxes.players);
    final syncQueueBox =
        await Hive.openBox<SyncQueueItem>(HiveBoxes.syncQueue);
    final settingsBox = await Hive.openBox<dynamic>(HiveBoxes.settings);

    return LocalDatabase._(
      attendanceBox: attendanceBox,
      transactionBox: transactionBox,
      playerBox: playerBox,
      syncQueueBox: syncQueueBox,
      settingsBox: settingsBox,
    );
  }

  /// Efface toutes les données locales (bouton « Réinitialiser » des réglages).
  Future<void> clearAll() async {
    await attendanceBox.clear();
    await transactionBox.clear();
    await playerBox.clear();
    await syncQueueBox.clear();
    await settingsBox.clear();
    notify(DbStore.attendance);
    notify(DbStore.transactions);
    notify(DbStore.players);
    notify(DbStore.syncQueue);
    notify(DbStore.settings);
  }

  Future<void> close() async {
    await _changes.close();
    await Hive.close();
  }
}
