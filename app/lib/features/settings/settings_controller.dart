import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../di/providers.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

/// État de configuration réactif (webhook, auteur, préférences).
final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).current;

  /// Recharge depuis le stockage (après une écriture faite par le moteur).
  void reload() => state = _repo.current;

  Future<void> _persist(AppSettings next) async {
    await _repo.save(next);
    state = next;
  }

  Future<void> saveWebhook({
    required String url,
    required String secret,
    String? sheetId,
  }) =>
      _persist(
        state.copyWith(
          webhookUrl: url.trim(),
          webhookSecret: secret.trim(),
          sheetId: (sheetId ?? '').trim().isEmpty ? null : sheetId!.trim(),
        ),
      );

  /// Définit l'auteur du pointage. L'identifiant reste stable si le nom est
  /// identique (traçabilité dans le Sheet : colonne `Auteur`).
  Future<void> setAuthor(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final keepId = state.authorName?.toLowerCase() == trimmed.toLowerCase() &&
        (state.authorId?.isNotEmpty ?? false);
    final id = keepId ? state.authorId! : const Uuid().v4();
    await _persist(state.copyWith(authorName: trimmed, authorId: id));
  }

  Future<void> setAutoSync(bool value) =>
      _persist(state.copyWith(autoSyncEnabled: value));

  Future<void> setSheetId(String? id) => _persist(
        state.copyWith(
          sheetId: (id == null || id.trim().isEmpty) ? null : id.trim(),
        ),
      );

  Future<void> clearLastError() =>
      _persist(state.copyWith(clearLastSyncError: true));
}
