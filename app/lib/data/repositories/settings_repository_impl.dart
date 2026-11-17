import 'dart:async';

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/enums/sync_target.dart';
import '../../domain/repositories/settings_repository.dart';

/// Implémentation Hive de la configuration locale (box `settings_v1`).
///
/// Les valeurs sont stockées à plat (clé/valeur) et **relues depuis la box** à
/// chaque accès : la configuration est toujours fraîche, y compris pour le
/// worker d'arrière-plan (qui n'a pas accès aux providers Riverpod) ou après une
/// réinitialisation des données. Le coût est nul : Hive garde la box en mémoire.
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._box) {
    // Génère l'identifiant d'appareil dès la première ouverture.
    _ensureDeviceId();
  }

  final Box<dynamic> _box;
  final StreamController<AppSettings> _controller =
      StreamController<AppSettings>.broadcast();

  static const String _kSyncTarget = 'sync_target';
  static const String _kSupabaseUrl = 'supabase_url';
  static const String _kSupabaseSecret = 'supabase_secret';
  static const String _kWebhookUrl = 'webhook_url';
  static const String _kWebhookSecret = 'webhook_secret';
  static const String _kDeviceId = 'device_id';
  static const String _kAuthorName = 'author_name';
  static const String _kAuthorId = 'author_id';
  static const String _kAutoSync = 'auto_sync';
  static const String _kLastSyncAt = 'last_sync_at';
  static const String _kLastSyncError = 'last_sync_error';
  static const String _kSheetId = 'sheet_id';
  static const String _kClubWebhookUrl = 'club_webhook_url';
  static const String _kClubWebhookSecret = 'club_webhook_secret';
  static const String _kClubSheetId = 'club_sheet_id';
  static const String _kClubConfigSyncedAt = 'club_config_synced_at';

  @override
  AppSettings get current => _read();

  @override
  Stream<AppSettings> watch() async* {
    yield _read();
    yield* _controller.stream;
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _box.putAll(<String, dynamic>{
      _kSyncTarget: settings.syncTarget.code,
      _kSupabaseUrl: settings.supabaseUrl.trim(),
      _kSupabaseSecret: settings.supabaseSecret.trim(),
      _kWebhookUrl: settings.webhookUrl.trim(),
      _kWebhookSecret: settings.webhookSecret.trim(),
      _kDeviceId: _ensureDeviceId(),
      _kAuthorName: settings.authorName,
      _kAuthorId: settings.authorId,
      _kAutoSync: settings.autoSyncEnabled,
      _kLastSyncAt: settings.lastSyncAt?.toIso8601String(),
      _kLastSyncError: settings.lastSyncError,
      _kSheetId: settings.sheetId,
      _kClubWebhookUrl: settings.clubWebhookUrl,
      _kClubWebhookSecret: settings.clubWebhookSecret,
      _kClubSheetId: settings.clubSheetId,
      _kClubConfigSyncedAt: settings.clubConfigSyncedAt?.toIso8601String(),
    });
    if (!_controller.isClosed) _controller.add(_read());
  }

  @override
  Future<void> updateAuthor({required String id, required String name}) =>
      save(current.copyWith(authorId: id, authorName: name));

  @override
  Future<void> updateWebhook({
    required String url,
    required String secret,
  }) =>
      save(current.copyWith(webhookUrl: url, webhookSecret: secret));

  @override
  Future<void> updateSupabase({
    required String url,
    required String secret,
  }) =>
      save(
        current.copyWith(
          syncTarget: SyncTarget.supabase,
          supabaseUrl: url,
          supabaseSecret: secret,
        ),
      );

  @override
  Future<void> updateSyncTarget(SyncTarget target) =>
      save(current.copyWith(syncTarget: target));

  @override
  Future<void> saveClubConfig({
    required String webhookUrl,
    required String webhookSecret,
    String? sheetId,
    DateTime? syncedAt,
  }) {
    final url = webhookUrl.trim();
    return save(
      current.copyWith(
        // Une URL vide côté serveur signifie « pas de Google Sheets pour ce
        // club » : on efface l'ancien webhook au lieu de garder une cible
        // fantôme, mais on horodate quand même la récupération (sinon l'appel
        // `config` serait rejoué à chaque reprise de l'application).
        clubWebhookUrl: url.isEmpty ? null : url,
        clubWebhookSecret: webhookSecret.trim(),
        clubSheetId: (sheetId ?? '').trim(),
        clubConfigSyncedAt: syncedAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Future<void> clearClubConfig() => save(current.copyWith(clearClubConfig: true));

  @override
  Future<void> recordSyncSuccess(DateTime at) => save(
        current.copyWith(lastSyncAt: at, clearLastSyncError: true),
      );

  @override
  Future<void> recordSyncFailure(String? error) => save(
        error == null
            ? current.copyWith(clearLastSyncError: true)
            : current.copyWith(lastSyncError: error),
      );

  String _ensureDeviceId() {
    final stored = (_box.get(_kDeviceId) as String?)?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    final generated = const Uuid().v4();
    // Écriture immédiate : l'identifiant doit survivre au redémarrage.
    unawaited(Future<void>.sync(() => _box.put(_kDeviceId, generated)));
    return generated;
  }

  AppSettings _read() {
    final lastSyncRaw = _box.get(_kLastSyncAt) as String?;
    final clubSyncedRaw = _box.get(_kClubConfigSyncedAt) as String?;

    return AppSettings(
      syncTarget: SyncTarget.fromCode(_box.get(_kSyncTarget) as String?),
      supabaseUrl: (_box.get(_kSupabaseUrl) as String?) ?? '',
      supabaseSecret: (_box.get(_kSupabaseSecret) as String?) ?? '',
      webhookUrl: (_box.get(_kWebhookUrl) as String?) ?? '',
      webhookSecret: (_box.get(_kWebhookSecret) as String?) ?? '',
      deviceId: _ensureDeviceId(),
      authorName: _box.get(_kAuthorName) as String?,
      authorId: _box.get(_kAuthorId) as String?,
      autoSyncEnabled: (_box.get(_kAutoSync) as bool?) ?? true,
      lastSyncAt: lastSyncRaw == null ? null : DateTime.tryParse(lastSyncRaw),
      lastSyncError: _box.get(_kLastSyncError) as String?,
      sheetId: _box.get(_kSheetId) as String?,
      clubWebhookUrl: _box.get(_kClubWebhookUrl) as String?,
      clubWebhookSecret: _box.get(_kClubWebhookSecret) as String?,
      clubSheetId: _box.get(_kClubSheetId) as String?,
      clubConfigSyncedAt:
          clubSyncedRaw == null ? null : DateTime.tryParse(clubSyncedRaw),
    );
  }
}
