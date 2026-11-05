import 'dart:async';

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/app_settings.dart';
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

  static const String _kWebhookUrl = 'webhook_url';
  static const String _kWebhookSecret = 'webhook_secret';
  static const String _kDeviceId = 'device_id';
  static const String _kAuthorName = 'author_name';
  static const String _kAuthorId = 'author_id';
  static const String _kAutoSync = 'auto_sync';
  static const String _kLastSyncAt = 'last_sync_at';
  static const String _kLastSyncError = 'last_sync_error';
  static const String _kSheetId = 'sheet_id';

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
      _kWebhookUrl: settings.webhookUrl.trim(),
      _kWebhookSecret: settings.webhookSecret.trim(),
      _kDeviceId: _ensureDeviceId(),
      _kAuthorName: settings.authorName,
      _kAuthorId: settings.authorId,
      _kAutoSync: settings.autoSyncEnabled,
      _kLastSyncAt: settings.lastSyncAt?.toIso8601String(),
      _kLastSyncError: settings.lastSyncError,
      _kSheetId: settings.sheetId,
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

    return AppSettings(
      webhookUrl: (_box.get(_kWebhookUrl) as String?) ?? '',
      webhookSecret: (_box.get(_kWebhookSecret) as String?) ?? '',
      deviceId: _ensureDeviceId(),
      authorName: _box.get(_kAuthorName) as String?,
      authorId: _box.get(_kAuthorId) as String?,
      autoSyncEnabled: (_box.get(_kAutoSync) as bool?) ?? true,
      lastSyncAt: lastSyncRaw == null ? null : DateTime.tryParse(lastSyncRaw),
      lastSyncError: _box.get(_kLastSyncError) as String?,
      sheetId: _box.get(_kSheetId) as String?,
    );
  }
}
