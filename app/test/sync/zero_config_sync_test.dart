import 'dart:convert';
import 'dart:io';

import 'package:dtnh_assistant_club/core/config/app_config.dart';
import 'package:dtnh_assistant_club/core/errors/app_exception.dart';
import 'package:dtnh_assistant_club/data/auth/auth_token_source.dart';
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
import 'package:dtnh_assistant_club/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Dépôt de réglages en mémoire (aucune dépendance à Hive).
class _MemorySettingsRepository implements SettingsRepository {
  _MemorySettingsRepository(this._settings);

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
    _settings = _settings.copyWith(supabaseUrl: url, supabaseSecret: secret);
  }

  @override
  Future<void> updateSyncTarget(SyncTarget target) async {
    _settings = _settings.copyWith(syncTarget: target);
  }

  @override
  Future<void> saveClubConfig({
    required String webhookUrl,
    required String webhookSecret,
    String? sheetId,
    DateTime? syncedAt,
  }) async {
    _settings = _settings.copyWith(
      clubWebhookUrl: webhookUrl.trim(),
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

class _FakeTokenSource extends AuthTokenSource {
  const _FakeTokenSource(this._token);

  final String? _token;

  @override
  Future<String?> currentAccessToken() async => _token;
}

const _configUrl = 'https://example.supabase.co/functions/v1/dtnh-sync';

/// Réglages d'un appareil neuf : aucune saisie, cible Supabase par défaut.
const _freshSettings = AppSettings(
  syncTarget: SyncTarget.appsScript,
  supabaseUrl: _configUrl,
  deviceId: 'device-1',
  authorName: 'Coach Tojo',
  authorId: 'user-uuid',
);

void main() {
  group('AppSettings — configuration sans saisie', () {
    test('un appareil neuf n a pas de cible Apps Script mais interroge Supabase',
        () {
      const settings = AppSettings(syncTarget: SyncTarget.appsScript);

      // Aucune URL de webhook : la cible Sheets n'est pas encore configurée…
      expect(settings.activeSyncUrl, isEmpty);
      expect(settings.hasSyncTarget, isFalse);
      // …mais l'endpoint de configuration est connu grâce au build.
      expect(settings.configEndpoint, isNotEmpty);
      expect(settings.isClubConfigFetched, isFalse);
    });

    test('la configuration du club se substitue au repli compile', () {
      const settings = AppSettings(
        syncTarget: SyncTarget.appsScript,
        supabaseUrl: _configUrl,
        clubWebhookUrl: 'https://script.google.com/macros/s/CLUB/exec',
        clubWebhookSecret: 'club-secret',
        clubSheetId: 'sheet-club',
      );

      expect(settings.hasClubConfig, isTrue);
      expect(
        settings.activeSyncUrl,
        'https://script.google.com/macros/s/CLUB/exec',
      );
      expect(settings.activeSyncSecret, 'club-secret');
      expect(settings.activeSheetId, 'sheet-club');
    });

    test('une saisie manuelle reste prioritaire sur la configuration du club',
        () {
      const settings = AppSettings(
        syncTarget: SyncTarget.appsScript,
        webhookUrl: 'https://script.google.com/macros/s/LOCAL/exec',
        webhookSecret: 'local-secret',
        clubWebhookUrl: 'https://script.google.com/macros/s/CLUB/exec',
        clubWebhookSecret: 'club-secret',
      );

      expect(
        settings.activeSyncUrl,
        'https://script.google.com/macros/s/LOCAL/exec',
      );
      expect(settings.activeSyncSecret, 'local-secret');
    });

    test('un secret absent ne rend plus la synchronisation "non configuree"',
        () {
      const settings = AppSettings(
        syncTarget: SyncTarget.supabase,
        supabaseUrl: 'https://example.supabase.co/functions/v1/dtnh-sync',
        authorName: 'Coach Tojo',
        authorId: 'user-uuid',
      );

      expect(settings.isSecretMissing, isTrue);
      // La session Google suffit : la cible est utilisable.
      expect(settings.hasSyncTarget, isTrue);
      expect(settings.isConfigured, isTrue);
    });

    test('clearClubConfig oublie URL, secret, sheet et horodatage', () {
      final settings = const AppSettings()
          .copyWith(
            clubWebhookUrl: 'https://script.google.com/macros/s/CLUB/exec',
            clubWebhookSecret: 'club-secret',
            clubSheetId: 'sheet-club',
            clubConfigSyncedAt: DateTime(2026, 11, 17),
          )
          .copyWith(clearClubConfig: true);

      expect(settings.clubWebhookUrl, isNull);
      expect(settings.clubWebhookSecret, isNull);
      expect(settings.clubSheetId, isNull);
      expect(settings.clubConfigSyncedAt, isNull);
      expect(settings.isClubConfigFetched, isFalse);
    });
  });

  group('AppsScriptClient — récupération de la configuration', () {
    test('envoie la session Google et renvoie la fiche du club', () async {
      Map<String, String>? seenHeaders;
      final client = AppsScriptClient(
        tokens: const _FakeTokenSource('jeton-google'),
        httpClient: MockClient((request) async {
          seenHeaders = request.headers;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['action'], 'config');
          // Le secret n'est pas exigé quand une session existe.
          expect(body.containsKey('secret'), isFalse);
          return http.Response(
            jsonEncode({
              'ok': true,
              'target': 'supabase',
              'sheets': {
                'webhookUrl': 'https://script.google.com/macros/s/CLUB/exec',
                'webhookSecret': 'club-secret',
                'sheetId': 'sheet-club',
              },
              'serverTime': '2026-11-17T08:00:00.000Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final club = await client.fetchClubConfig(webhookUrl: _configUrl);

      expect(seenHeaders?['Authorization'], 'Bearer jeton-google');
      expect(club.hasSheets, isTrue);
      expect(club.webhookUrl, 'https://script.google.com/macros/s/CLUB/exec');
      expect(club.webhookSecret, 'club-secret');
      expect(club.sheetId, 'sheet-club');
      expect(club.serverTime, DateTime.utc(2026, 11, 17, 8));
    });

    test('club 100 % Supabase : reponse valide, aucune erreur', () async {
      final client = AppsScriptClient(
        tokens: const _FakeTokenSource('jeton-google'),
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'ok': true,
              'target': 'supabase',
              'sheets': {'webhookUrl': null, 'webhookSecret': null},
              'serverTime': '2026-11-17T08:00:00.000Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final club = await client.fetchClubConfig(webhookUrl: _configUrl);

      expect(club.hasSheets, isFalse);
      expect(club.webhookUrl, isNull);
    });

    test('401 remonte une erreur non reessayable', () async {
      final client = AppsScriptClient(
        tokens: const _FakeTokenSource('jeton-expire'),
        httpClient: MockClient((request) async => http.Response('', 401)),
      );

      expect(
        () => client.fetchClubConfig(webhookUrl: _configUrl),
        throwsA(
          isA<SyncTransportException>()
              .having((error) => error.statusCode, 'statusCode', 401)
              .having((error) => error.isRetryable, 'isRetryable', isFalse),
        ),
      );
    });

    test('URL vide : erreur de configuration explicite', () async {
      final client = AppsScriptClient(tokens: const _FakeTokenSource(null));

      expect(
        () => client.fetchClubConfig(webhookUrl: ''),
        throwsA(isA<SyncConfigurationException>()),
      );
    });
  });

  group('SyncEngine — auto-reparation de la configuration', () {
    late Directory tempDir;
    late LocalDatabase database;
    late SyncQueueRepositoryImpl queue;
    late AttendanceRepositoryImpl attendance;
    late _MemorySettingsRepository settings;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dtnh_autoconfig_');
      database = await LocalDatabase.open(directory: tempDir.path);
      // `SyncQueueDao` prend la base entière (elle résout elle-même sa box).
      queue = SyncQueueRepositoryImpl(dao: SyncQueueDao(database));
      attendance = AttendanceRepositoryImpl(
        dao: AttendanceDao(database),
        queue: queue,
      );
      settings = _MemorySettingsRepository(_freshSettings);
    });

    tearDown(() async {
      await database.close();
      await tempDir.delete(recursive: true);
    });

    Future<void> seedAttendance({String playerId = 'p1'}) async {
      await attendance.saveSession(
        category: TeamCategory.u16,
        date: DateTime(2026, 11, 5),
        players: [
          Player(
            id: playerId,
            fullName: 'Rakotobe Fandresena',
            category: TeamCategory.u16,
            jerseyNumber: 3,
            createdAt: DateTime(2026, 11, 5),
            updatedAt: DateTime(2026, 11, 5),
          ),
        ],
        statuses: {playerId: AttendanceStatus.present},
        authorId: 'user-uuid',
        authorName: 'Coach Tojo',
      );
    }

    test('sans URL, la session Google suffit : configuration recuperee puis lot envoye',
        () async {
      await seedAttendance();

      final actions = <String>[];
      final client = AppsScriptClient(
        tokens: const _FakeTokenSource('jeton-google'),
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final action = body['action'] as String;
          actions.add(action);
          if (action == 'config') {
            return http.Response(
              jsonEncode({
                'ok': true,
                'target': 'supabase',
                'sheets': {
                  'webhookUrl':
                      'https://script.google.com/macros/s/CLUB/exec',
                  'webhookSecret': 'club-secret',
                  'sheetId': 'sheet-club',
                },
                'serverTime': '2026-11-17T08:00:00.000Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'results': [
                for (final item in body['items'] as List<dynamic>)
                  {
                    'id': (item as Map<String, dynamic>)['id'],
                    'status': 'ok',
                  },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final report = await SyncEngine(
        queue: queue,
        client: client,
        settings: settings,
      ).pushPending();

      expect(actions, ['config', 'push']);
      expect(report.succeeded, 1);
      expect(
        settings.current.clubWebhookUrl,
        'https://script.google.com/macros/s/CLUB/exec',
      );
      expect(settings.current.hasClubConfig, isTrue);
    });

    test('sans session et sans URL, erreur de configuration explicite',
        () async {
      await seedAttendance();

      final client = AppsScriptClient(
        tokens: const _FakeTokenSource(null),
        httpClient: MockClient(
          (request) async => fail('aucun appel reseau ne doit partir'),
        ),
      );

      expect(
        () => SyncEngine(
          queue: queue,
          client: client,
          settings: settings,
        ).pushPending(),
        throwsA(isA<SyncConfigurationException>()),
      );
    });
  });

  test('AppConfig expose un endpoint Supabase compile', () {
    // Garantit que l'auto-configuration a bien un point d'entree dans le build
    // (sinon un appareil neuf n'aurait rien a interroger).
    expect(AppConfig.supabaseSyncUrl.trim(), isNotEmpty);
    expect(AppConfig.supabaseSyncUrl, startsWith('https://'));
  });
}
