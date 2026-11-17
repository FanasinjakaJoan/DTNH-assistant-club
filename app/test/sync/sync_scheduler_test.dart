import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dtnh_assistant_club/core/errors/app_exception.dart';
import 'package:dtnh_assistant_club/data/local/dao/attendance_dao.dart';
import 'package:dtnh_assistant_club/data/local/dao/sync_queue_dao.dart';
import 'package:dtnh_assistant_club/data/local/local_database.dart';
import 'package:dtnh_assistant_club/data/remote/apps_script_client.dart';
import 'package:dtnh_assistant_club/data/repositories/attendance_repository_impl.dart';
import 'package:dtnh_assistant_club/data/repositories/sync_queue_repository_impl.dart';
import 'package:dtnh_assistant_club/domain/entities/app_settings.dart';
import 'package:dtnh_assistant_club/domain/entities/player.dart';
import 'package:dtnh_assistant_club/domain/enums/attendance_status.dart';
import 'package:dtnh_assistant_club/domain/enums/sync_target.dart';
import 'package:dtnh_assistant_club/domain/enums/team_category.dart';
import 'package:dtnh_assistant_club/domain/repositories/settings_repository.dart';
import 'package:dtnh_assistant_club/domain/repositories/sync_queue_repository.dart';
import 'package:dtnh_assistant_club/sync/network_status.dart';
import 'package:dtnh_assistant_club/sync/sync_engine.dart';
import 'package:dtnh_assistant_club/sync/sync_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeSettings implements SettingsRepository {
  _FakeSettings(this._settings);

  AppSettings _settings;

  @override
  AppSettings get current => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;

  @override
  Future<void> updateAuthor({required String id, required String name}) async {}

  @override
  Future<void> updateWebhook({required String url, required String secret}) async {}

  @override
  Future<void> updateSupabase({required String url, required String secret}) async {}

  @override
  Future<void> updateSyncTarget(SyncTarget target) async {}

  @override
  Future<void> recordSyncSuccess(DateTime at) async {
    _settings = _settings.copyWith(lastSyncAt: at, clearLastSyncError: true);
  }

  @override
  Future<void> recordSyncFailure(String? error) async {}

  @override

  Future<void> saveClubConfig({

    required String webhookUrl,

    required String webhookSecret,

    String? sheetId,

    DateTime? syncedAt,

  }) async {

    _settings = _settings.copyWith(

      clubWebhookUrl: webhookUrl.trim().isEmpty ? null : webhookUrl.trim(),

      clubWebhookSecret: webhookSecret,

      clubSheetId: sheetId,

      clubConfigSyncedAt: syncedAt ?? DateTime.now(),

    );

  }


  @override

  Future<void> clearClubConfig() async {

    _settings = _settings.copyWith(clearClubConfig: true);

  }


  @override
  Stream<AppSettings> watch() => Stream<AppSettings>.value(_settings);
}

/// Faux état réseau : on pilote explicitement les transitions, ce qui rend les
/// tests déterministes (aucun canal de plateforme, aucun minuteur système).
class _FakeNetwork implements NetworkStatus {
  _FakeNetwork(this._online);

  bool _online;
  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  @override
  Future<bool> checkOnline() async => _online;

  @override
  Stream<bool> get changes => _controller.stream;

  void emit(bool online) {
    _online = online;
    _controller.add(online);
  }

  Future<void> close() => _controller.close();
}

void main() {
  late Directory tempDir;
  late LocalDatabase database;
  late SyncQueueRepositoryImpl queue;
  late AttendanceRepositoryImpl attendance;
  late int sentBatches;

  const settings = AppSettings(
    syncTarget: SyncTarget.appsScript,
    webhookUrl: 'https://script.google.com/macros/s/ABC/exec',
    webhookSecret: 'secret-123',
    deviceId: 'device-1',
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dtnh_sched_');
    database = await LocalDatabase.open(directory: tempDir.path);
    queue = SyncQueueRepositoryImpl(dao: SyncQueueDao(database));
    attendance = AttendanceRepositoryImpl(
      dao: AttendanceDao(database),
      queue: queue,
    );
    sentBatches = 0;
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  AppsScriptClient countingClient() => AppsScriptClient(
        httpClient: MockClient((request) async {
          sentBatches++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final items = body['items'] as List<dynamic>;
          return http.Response(
            jsonEncode({
              'ok': true,
              'results': items
                  .map((raw) => {
                        'id': (raw as Map<String, dynamic>)['id'],
                        'status': 'ok',
                      })
                  .toList(),
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

  SyncScheduler buildScheduler({
    required _FakeNetwork network,
    AppSettings appSettings = settings,
    Duration debounce = const Duration(milliseconds: 20),
    Stream<SyncQueueCounters>? queueChanges,
  }) {
    final engine = SyncEngine(
      queue: queue,
      client: countingClient(),
      settings: _FakeSettings(appSettings),
    );
    return SyncScheduler(
      engine: engine,
      settings: _FakeSettings(appSettings),
      network: network,
      queueChanges: queueChanges,
      debounce: debounce,
      writeDebounce: debounce,
      enablePeriodic: false,
    );
  }

  Future<void> seedPendingAttendance() async {
    await attendance.saveSession(
      category: TeamCategory.u16,
      date: DateTime(2026, 11, 5),
      players: [
        Player(
          id: 'p1',
          fullName: 'A',
          category: TeamCategory.u16,
          createdAt: DateTime(2026, 11, 5),
          updatedAt: DateTime(2026, 11, 5),
        ),
      ],
      statuses: {'p1': AttendanceStatus.present},
      authorId: 'coach-1',
      authorName: 'Coach Tojo',
    );
  }

  group('SyncScheduler — déclenchement automatique', () {
    test('synchronise au démarrage si des données attendent', () async {
      await seedPendingAttendance();
      final network = _FakeNetwork(true);
      final scheduler = buildScheduler(network: network);

      await scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(sentBatches, 1);
      expect(await queue.counters().then((c) => c.outstanding), 0);

      await scheduler.dispose();
      await network.close();
    });

    test('ne fait aucun appel réseau quand la file est vide', () async {
      final network = _FakeNetwork(true);
      final scheduler = buildScheduler(network: network);

      await scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // Aucun envoi : `lastSyncAt` ne doit pas avancer à vide.
      expect(sentBatches, 0);

      await scheduler.dispose();
      await network.close();
    });

    test('synchronise au retour en ligne (transition hors-ligne -> ligne)',
        () async {
      final network = _FakeNetwork(false);
      final scheduler = buildScheduler(network: network);

      await scheduler.start();
      await seedPendingAttendance();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // Hors-ligne : rien ne part, la donnée reste en file.
      expect(sentBatches, 0);
      expect(await queue.counters().then((c) => c.outstanding), 1);

      network.emit(true);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(sentBatches, 1);
      expect(await queue.counters().then((c) => c.outstanding), 0);

      await scheduler.dispose();
      await network.close();
    });

    test('synchronise à la reprise de l\'application', () async {
      final network = _FakeNetwork(true);
      final scheduler = buildScheduler(network: network);

      await scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sentBatches, 0);

      await seedPendingAttendance();
      scheduler.onAppResumed();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(sentBatches, 1);

      await scheduler.dispose();
      await network.close();
    });

    test('respecte la désactivation de la synchronisation automatique',
        () async {
      await seedPendingAttendance();
      final network = _FakeNetwork(true);
      final scheduler = buildScheduler(
        network: network,
        appSettings: settings.copyWith(autoSyncEnabled: false),
      );

      await scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(sentBatches, 0);
      expect(await queue.counters().then((c) => c.outstanding), 1);

      await scheduler.dispose();
      await network.close();
    });

    test('un déclenchement pendant un envoi n\'est pas perdu', () async {
      await seedPendingAttendance();
      final network = _FakeNetwork(true);
      final scheduler = buildScheduler(
        network: network,
        debounce: const Duration(milliseconds: 5),
      );

      await scheduler.start();
      // On demande un second passage alors que le premier est encore en vol.
      scheduler.onAppResumed();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // La file est vidée, donc le second passage ne renvoie rien : l'essentiel
      // est qu'aucun envoi ne soit resté bloqué.
      expect(await queue.counters().then((c) => c.outstanding), 0);

      await scheduler.dispose();
      await network.close();
    });

    test('synchronise après une écriture locale, sans action du staff',
        () async {
      final network = _FakeNetwork(true);
      final scheduler = buildScheduler(
        network: network,
        // Faux flux d'écritures : le vrai est branché sur la file Hive.
        queueChanges: queue.watchCounters(),
      );

      await scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // Démarrage à vide : rien à envoyer.
      expect(sentBatches, 0);

      // Le staff pointe une séance : une écriture entre dans la file.
      await seedPendingAttendance();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(sentBatches, 1);
      expect(await queue.counters().then((c) => c.outstanding), 0);

      await scheduler.dispose();
      await network.close();
    });

    test('dispose annule le minuteur : plus aucun envoi après', () async {
      await seedPendingAttendance();
      final network = _FakeNetwork(true);
      final scheduler = buildScheduler(network: network);

      await scheduler.start();
      await scheduler.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(sentBatches, 0);
      await network.close();
    });
  });

  group('AppsScriptClient — message d\'erreur 5xx', () {
    test('remonte le diagnostic BOOT_ERROR de la fonction déployée', () async {
      final client = AppsScriptClient(
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({
                'code': 'BOOT_ERROR',
                'message': 'Function failed to start (please check logs)',
              }),
              503,
              headers: {'content-type': 'application/json'},
            )),
      );

      await expectLater(
        client.sendBatch(
          webhookUrl: 'https://osjz.supabase.co/functions/v1/dtnh-sync',
          secret: 'secret-123',
          deviceId: 'device-1',
          batchId: 'batch-1',
          entries: const [],
        ),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.message,
            'message',
            allOf(contains('503'), contains('Function failed to start')),
          ),
        ),
      );
    });

    test('garde un message générique si le corps n\'est pas exploitable',
        () async {
      final client = AppsScriptClient(
        httpClient: MockClient((_) async => http.Response('gateway', 502)),
      );

      await expectLater(
        client.sendBatch(
          webhookUrl: 'https://osjz.supabase.co/functions/v1/dtnh-sync',
          secret: 'secret-123',
          deviceId: 'device-1',
          batchId: 'batch-1',
          entries: const [],
        ),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.message,
            'message',
            contains('indisponible'),
          ),
        ),
      );
    });
  });
}
