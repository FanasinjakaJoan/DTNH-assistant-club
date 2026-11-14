import 'dart:convert';
import 'dart:io';

import 'package:dtnh_assistant_club/core/errors/app_exception.dart';
import 'package:dtnh_assistant_club/data/local/dao/attendance_dao.dart';
import 'package:dtnh_assistant_club/data/local/dao/sync_queue_dao.dart';
import 'package:dtnh_assistant_club/data/local/local_database.dart';
import 'package:dtnh_assistant_club/data/auth/auth_token_source.dart';
import 'package:dtnh_assistant_club/data/remote/apps_script_client.dart';
import 'package:dtnh_assistant_club/data/remote/sync_payloads.dart';
import 'package:dtnh_assistant_club/data/repositories/attendance_repository_impl.dart';
import 'package:dtnh_assistant_club/data/repositories/sync_queue_repository_impl.dart';
import 'package:dtnh_assistant_club/domain/entities/app_settings.dart';
import 'package:dtnh_assistant_club/domain/entities/attendance_entry.dart';
import 'package:dtnh_assistant_club/domain/entities/player.dart';
import 'package:dtnh_assistant_club/domain/enums/attendance_status.dart';
import 'package:dtnh_assistant_club/domain/enums/sync_enums.dart';
import 'package:dtnh_assistant_club/domain/enums/sync_target.dart';
import 'package:dtnh_assistant_club/domain/enums/team_category.dart';
import 'package:dtnh_assistant_club/domain/repositories/settings_repository.dart';
import 'package:dtnh_assistant_club/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Faux dépôt de réglages (sans Hive) pour tester le moteur isolément.
class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this._settings);

  AppSettings _settings;
  String? lastError;

  @override
  AppSettings get current => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;

  @override
  Future<void> updateAuthor({required String id, required String name}) async {
    _settings = _settings.copyWith(authorId: id, authorName: name);
  }

  @override
  Future<void> updateWebhook({
    required String url,
    required String secret,
  }) async {
    _settings = _settings.copyWith(webhookUrl: url, webhookSecret: secret);
  }

  @override
  Future<void> updateSupabase({
    required String url,
    required String secret,
  }) async {
    _settings = _settings.copyWith(
      syncTarget: SyncTarget.supabase,
      supabaseUrl: url,
      supabaseSecret: secret,
    );
  }

  @override
  Future<void> updateSyncTarget(SyncTarget target) async {
    _settings = _settings.copyWith(syncTarget: target);
  }

  @override
  Future<void> recordSyncSuccess(DateTime at) async {
    _settings = _settings.copyWith(lastSyncAt: at, clearLastSyncError: true);
    lastError = null;
  }

  @override
  Future<void> recordSyncFailure(String? error) async {
    lastError = error;
  }

  @override
  Stream<AppSettings> watch() => Stream<AppSettings>.value(_settings);
}

const _configuredSettings = AppSettings(
  // Cible explicite : sinon ce sont les valeurs compilées (Supabase) qui
  // s'appliquent, et le test ne contrôlerait plus l'URL envoyée.
  syncTarget: SyncTarget.appsScript,
  webhookUrl: 'https://script.google.com/macros/s/ABC/exec',
  webhookSecret: 'secret-123',
  deviceId: 'device-1',
);

http.Response _okResponse(Map<String, dynamic> body, List<dynamic> items) =>
    http.Response(
      jsonEncode({
        ...body,
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

void main() {
  group('SyncPayloads', () {
    test('respecte les clés attendues par Apps Script', () {
      final now = DateTime(2026, 11, 5, 8, 45);
      final entry = AttendanceEntry(
        id: 'entry-1',
        sessionId: 'session-1',
        sessionDate: DateTime(2026, 11, 5),
        recordedAt: now,
        category: TeamCategory.u16,
        playerId: 'p1',
        playerName: 'Rakotobe Fandresena',
        jerseyNumber: 3,
        status: AttendanceStatus.present,
        authorId: 'coach-1',
        authorName: 'Coach Tojo',
        updatedAt: now,
      );

      final payload = SyncPayloads.attendance(entry);

      expect(payload['id'], 'entry-1');
      expect(payload['date'], '2026-11-05');
      expect(payload['categorie'], 'U16');
      expect(payload['joueur'], 'Rakotobe Fandresena');
      expect(payload['statut'], 'PRESENT');
      expect(payload['auteur'], 'Coach Tojo');
      expect(payload['heure'], '08:45');
      expect(payload['numero'], 3);
      // Traçabilité Supabase (colonne author_id).
      expect(payload['auteurId'], 'coach-1');
      expect(payload['sessionId'], 'session-1');
      // Le SyncTimestamp est généré côté serveur : le client ne l'envoie pas.
      expect(payload.containsKey('syncTimestamp'), isFalse);
    });

    test('expose les clés attendues pour les joueurs', () {
      final player = Player(
        id: 'p1',
        fullName: 'Rasoa Miora',
        category: TeamCategory.u14u15,
        jerseyNumber: 7,
        phone: '0340000000',
        createdAt: DateTime(2026, 11, 5),
        updatedAt: DateTime(2026, 11, 5),
      );

      final payload = SyncPayloads.player(player);

      expect(payload['id'], 'p1');
      expect(payload['nom'], 'Rasoa Miora');
      expect(payload['categorie'], 'U14-U15');
      expect(payload['numero'], 7);
      expect(payload['telephone'], '0340000000');
      expect(payload['actif'], isTrue);
      expect(payload['updatedAt'], isA<String>());
    });
  });

  group('SyncEngine', () {
    late Directory tempDir;
    late LocalDatabase database;
    late SyncQueueRepositoryImpl queue;
    late AttendanceRepositoryImpl attendance;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dtnh_sync_');
      database = await LocalDatabase.open(directory: tempDir.path);
      queue = SyncQueueRepositoryImpl(dao: SyncQueueDao(database));
      attendance = AttendanceRepositoryImpl(
        dao: AttendanceDao(database),
        queue: queue,
      );
    });

    tearDown(() async {
      await database.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Future<void> seedAttendance({
      required String playerId,
      required String name,
      AttendanceStatus status = AttendanceStatus.present,
    }) async {
      await attendance.saveSession(
        category: TeamCategory.u16,
        date: DateTime(2026, 11, 5),
        players: [
          Player(
            id: playerId,
            fullName: name,
            category: TeamCategory.u16,
            jerseyNumber: 3,
            createdAt: DateTime(2026, 11, 5),
            updatedAt: DateTime(2026, 11, 5),
          ),
        ],
        statuses: {playerId: status},
        authorId: 'coach-1',
        authorName: 'Coach Tojo',
      );
    }

    test('refuse de synchroniser sans cible configurée', () async {
      final engine = SyncEngine(
        queue: queue,
        client: AppsScriptClient(),
        // Cible Apps Script sans URL : configuration incomplète.
        settings: _FakeSettingsRepository(
          const AppSettings(syncTarget: SyncTarget.appsScript),
        ),
      );

      await expectLater(
        engine.pushPending(),
        throwsA(isA<SyncConfigurationException>()),
      );
    });

    test('marque les items SYNCED et propage l\'état aux entités', () async {
      await seedAttendance(playerId: 'p1', name: 'A');

      late Map<String, dynamic> received;
      final client = AppsScriptClient(
        httpClient: MockClient((request) async {
          received = jsonDecode(request.body) as Map<String, dynamic>;
          final items = received['items'] as List<dynamic>;
          return _okResponse({'ok': true, 'message': 'ok'}, items);
        }),
      );

      final settings = _FakeSettingsRepository(_configuredSettings);
      final engine = SyncEngine(
        queue: queue,
        client: client,
        settings: settings,
      );

      final report = await engine.pushPending();

      expect(report.attempted, 1);
      expect(report.succeeded, 1);
      expect(report.failed, 0);
      expect(report.isSuccess, isTrue);
      expect(received['secret'], 'secret-123');
      expect(received['deviceId'], 'device-1');
      expect(received['items'] as List<dynamic>, hasLength(1));

      final counters = await queue.counters();
      expect(counters.pending, 0);
      expect(counters.synced, 1);
      expect(settings.current.lastSyncAt, isNotNull);

      final entries = await attendance.entriesForSession(
        category: TeamCategory.u16,
        date: DateTime(2026, 11, 5),
      );
      expect(entries.single.syncState, SyncState.synced);
      expect(entries.single.syncedAt, isNotNull);
    });

    test('un item refusé passe en ERROR sans bloquer les autres', () async {
      await seedAttendance(playerId: 'p1', name: 'OK');
      await seedAttendance(playerId: 'p2', name: 'REFUSÉ');

      final client = AppsScriptClient(
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final items = body['items'] as List<dynamic>;
          final results = items.map((raw) {
            final map = raw as Map<String, dynamic>;
            final data = map['data'] as Map<String, dynamic>;
            final ok = data['joueur'] != 'REFUSÉ';
            return {
              'id': map['id'],
              'status': ok ? 'ok' : 'error',
              'error': ok ? null : 'Ligne invalide (test)',
            };
          }).toList();
          return http.Response(
            jsonEncode({
              'ok': false,
              'message': 'partiel',
              'results': results,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final engine = SyncEngine(
        queue: queue,
        client: client,
        settings: _FakeSettingsRepository(_configuredSettings),
      );

      final report = await engine.pushPending();

      expect(report.succeeded, 1);
      expect(report.failed, 1);

      final counters = await queue.counters();
      expect(counters.synced, 1);
      expect(counters.error, 1);

      final pending = await queue.pendingBatch(limit: 10);
      final failed = pending.firstWhere((item) => item.status == SyncState.error);
      expect(failed.attempts, 1);
      expect(failed.lastError, contains('Ligne invalide'));
    });

    test('panne réseau : tentative comptée et erreur remontée', () async {
      await seedAttendance(playerId: 'p1', name: 'A');

      final client = AppsScriptClient(
        httpClient: MockClient((request) async {
          throw const SocketException('Network unreachable');
        }),
      );

      final settings = _FakeSettingsRepository(_configuredSettings);
      final engine = SyncEngine(
        queue: queue,
        client: client,
        settings: settings,
      );

      final report = await engine.pushPending();

      expect(report.error, isNotNull);
      expect(report.failed, 1);
      expect((await queue.counters()).error, 1);
      expect(settings.lastError, isNotNull);
    });

    test('un item en erreur peut être réessayé après réinitialisation',
        () async {
      await seedAttendance(playerId: 'p1', name: 'A');

      var calls = 0;
      final client = AppsScriptClient(
        httpClient: MockClient((request) async {
          calls++;
          if (calls == 1) {
            return http.Response('Service unavailable', 503);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final items = body['items'] as List<dynamic>;
          return _okResponse({'ok': true, 'message': 'ok'}, items);
        }),
      );

      final engine = SyncEngine(
        queue: queue,
        client: client,
        settings: _FakeSettingsRepository(_configuredSettings),
      );

      final first = await engine.pushPending();
      expect(first.failed, 1);
      expect((await queue.counters()).error, 1);

      for (final item in await queue.pendingBatch(limit: 10)) {
        await queue.resetForRetry(item.id);
      }

      final second = await engine.pushPending();
      expect(second.succeeded, 1);
      expect((await queue.counters()).synced, 1);
    });

    group('identite Google', () {
      test('le JWT de session est presente dans X-DTNH-Auth', () async {
        await seedAttendance(playerId: 'p1', name: 'A');

        Map<String, String>? seen;
        final client = AppsScriptClient(
          tokens: const _FakeTokenSource('jeton-google-123'),
          httpClient: MockClient((request) async {
            seen = request.headers;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return _okResponse(
              {'ok': true, 'message': 'ok'},
              body['items'] as List<dynamic>,
            );
          }),
        );

        final report = await SyncEngine(
          queue: queue,
          client: client,
          settings: _FakeSettingsRepository(_configuredSettings),
        ).pushPending();

        expect(report.succeeded, 1);
        expect(seen?['X-DTNH-Auth'], 'Bearer jeton-google-123');
      });

      test('sans session, aucun en-tete identite n est ajoute', () async {
        await seedAttendance(playerId: 'p1', name: 'A');

        Map<String, String>? seen;
        final client = AppsScriptClient(
          tokens: const _FakeTokenSource(null),
          httpClient: MockClient((request) async {
            seen = request.headers;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return _okResponse(
              {'ok': true, 'message': 'ok'},
              body['items'] as List<dynamic>,
            );
          }),
        );

        final report = await SyncEngine(
          queue: queue,
          client: client,
          settings: _FakeSettingsRepository(_configuredSettings),
        ).pushPending();

        expect(report.succeeded, 1);
        expect(seen?.containsKey('X-DTNH-Auth'), isFalse);
      });
    });
  });
}

/// Session simulee : renvoie un jeton fixe, ou `null` en mode hors-ligne.
class _FakeTokenSource extends AuthTokenSource {
  const _FakeTokenSource(this._token);

  final String? _token;

  @override
  Future<String?> currentAccessToken() async => _token;
}
