import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/auth/auth_service.dart';
import '../../di/providers.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/enums/sync_target.dart';
import '../../domain/repositories/settings_repository.dart';

/// État de configuration réactif (cible de sync, auteur, préférences).
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

  /// Configure l'Edge Function Supabase et bascule la cible sur Supabase.
  ///
  /// Laisser les deux champs vides revient à utiliser la configuration
  /// compilée dans l'application (`AppConfig`) : c'est le cas normal pour le
  /// staff du club, qui n'a rien à saisir.
  Future<void> saveSupabase({required String url, required String secret}) =>
      _persist(
        state.copyWith(
          syncTarget: SyncTarget.supabase,
          supabaseUrl: url.trim(),
          supabaseSecret: secret.trim(),
        ),
      );

  /// Choisit la destination des envois (Supabase ou Google Sheets).
  Future<void> setSyncTarget(SyncTarget target) =>
      _persist(state.copyWith(syncTarget: target));

  Future<void> saveWebhook({
    required String url,
    required String secret,
    String? sheetId,
  }) =>
      _persist(
        state.copyWith(
          syncTarget: SyncTarget.appsScript,
          webhookUrl: url.trim(),
          webhookSecret: secret.trim(),
          sheetId: (sheetId ?? '').trim().isEmpty ? null : sheetId!.trim(),
        ),
      );

  /// Définit l'auteur à partir de la session Google : l'identifiant stable
  /// devient l'UUID Supabase, ce qui relie chaque pointage à un compte réel
  /// (et permettra de durcir la RLS sur `auth.uid()`).
  Future<void> setAuthenticatedAuthor(AuthUser user) =>
      _persist(state.copyWith(authorName: user.displayName, authorId: user.id));

  /// Définit l'auteur du pointage. L'identifiant reste stable si le nom est
  /// identique (traçabilité dans les colonnes `Auteur`).
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
