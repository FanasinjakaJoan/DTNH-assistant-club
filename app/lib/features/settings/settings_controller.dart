import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../data/auth/auth_service.dart';
import '../../di/providers.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/enums/sync_target.dart';
import '../../domain/repositories/settings_repository.dart';

/// État de configuration réactif (cible de sync, auteur, préférences).
final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Résultat d'une tentative de configuration automatique.
enum ClubConfigOutcome {
  /// La configuration a été récupérée et enregistrée.
  applied,

  /// Le serveur a répondu, mais le club n'utilise pas Google Sheets.
  appliedWithoutSheets,

  /// Aucune session Google : rien à récupérer pour l'instant.
  notSignedIn,

  /// Le serveur n'a pas pu être joint (hors-ligne) : on garde le repli local.
  offline,

  /// Appel authentifié refusé (session expirée) : reconnexion nécessaire.
  unauthorized,

  /// Erreur serveur ou configuration incomplète côté Supabase.
  failed,
}

/// État observable de la récupération de configuration (bandeau des réglages).
class ClubConfigStatus {
  const ClubConfigStatus({
    this.isLoading = false,
    this.outcome,
    this.error,
  });

  final bool isLoading;
  final ClubConfigOutcome? outcome;
  final String? error;

  ClubConfigStatus copyWith({
    bool? isLoading,
    ClubConfigOutcome? outcome,
    String? error,
    bool clearOutcome = false,
    bool clearError = false,
  }) =>
      ClubConfigStatus(
        isLoading: isLoading ?? this.isLoading,
        outcome: clearOutcome ? null : (outcome ?? this.outcome),
        error: clearError ? null : (error ?? this.error),
      );
}

/// Récupération de la configuration du club auprès de l'Edge Function.
///
/// **Zéro configuration manuelle** : dès qu'un membre se connecte avec Google,
/// ce provider interroge `dtnh-sync` (action `config`) et récupère l'URL + le
/// secret du webhook Sheets, qui ne vivent plus dans le build public. Un échec
/// réseau ne bloque rien : on retombe sur les valeurs déjà connues (saisie
/// locale, cache de la dernière récupération, valeurs compilées).
final clubConfigStatusProvider =
    NotifierProvider<ClubConfigStatusController, ClubConfigStatus>(
  ClubConfigStatusController.new,
);

class ClubConfigStatusController extends Notifier<ClubConfigStatus> {
  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  @override
  ClubConfigStatus build() => const ClubConfigStatus();

  /// Récupère la configuration, sauf si elle est déjà à jour (et non forcé).
  Future<ClubConfigOutcome> refresh({bool force = false}) async {
    if (state.isLoading) {
      return state.outcome ?? ClubConfigOutcome.failed;
    }
    final current = _repo.current;
    if (!force && current.isClubConfigFetched) {
      return state.outcome ??
          (current.hasClubConfig
              ? ClubConfigOutcome.applied
              : ClubConfigOutcome.appliedWithoutSheets);
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final client = ref.read(appsScriptClientProvider);
      // Toujours l'Edge Function Supabase : c'est le seul endpoint qui
      // distribue la configuration. Utiliser `activeSyncUrl` échouerait sur un
      // appareil neuf dont la cible serait encore Apps Script.
      final club = await client.fetchClubConfig(
        webhookUrl: current.configEndpoint,
        secret: current.configSecret,
      );
      await _repo.saveClubConfig(
        webhookUrl: club.webhookUrl ?? '',
        webhookSecret: club.webhookSecret ?? '',
        sheetId: club.sheetId,
        syncedAt: club.serverTime ?? DateTime.now(),
      );
      final saved = _repo.current;
      final outcome = saved.hasClubConfig
          ? ClubConfigOutcome.applied
          : ClubConfigOutcome.appliedWithoutSheets;
      state = ClubConfigStatus(outcome: outcome);
      return outcome;
    } on SyncOfflineException catch (error) {
      state = ClubConfigStatus(
        outcome: ClubConfigOutcome.offline,
        error: error.message,
      );
      return ClubConfigOutcome.offline;
    } on SyncTransportException catch (error) {
      final outcome = error.statusCode == 401 || error.statusCode == 403
          ? ClubConfigOutcome.unauthorized
          : error.isRetryable
              ? ClubConfigOutcome.offline
              : ClubConfigOutcome.failed;
      state = ClubConfigStatus(outcome: outcome, error: error.message);
      return outcome;
    } on SyncConfigurationException catch (error) {
      state = ClubConfigStatus(
        outcome: ClubConfigOutcome.failed,
        error: error.message,
      );
      return ClubConfigOutcome.failed;
    } on AppException catch (error) {
      state = ClubConfigStatus(
        outcome: ClubConfigOutcome.failed,
        error: error.message,
      );
      return ClubConfigOutcome.failed;
    } catch (error) {
      state = ClubConfigStatus(
        outcome: ClubConfigOutcome.failed,
        error: 'Configuration indisponible : $error',
      );
      return ClubConfigOutcome.failed;
    }
  }

  /// Déconnexion : la configuration reçue du club est oubliée.
  Future<void> forget() async {
    await _repo.clearClubConfig();
    state = const ClubConfigStatus();
  }
}

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
  /// Laisser les deux champs vides revient à utiliser la configuration du club
  /// puis, à défaut, celle compilée dans l'application (`AppConfig`) : c'est le
  /// cas normal pour le staff, qui n'a rien à saisir.
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
  /// devient l'UUID Supabase, ce qui relie chaque pointage à un compte réel.
  ///
  /// C'est aussi le point d'entrée de la **configuration automatique** : une
  /// session ouverte suffit à recevoir URL et secret de la cible Sheets.
  Future<void> setAuthenticatedAuthor(AuthUser user) async {
    final needsConfig =
        state.authorId != user.id || !state.isClubConfigFetched;
    await _persist(
      state.copyWith(authorName: user.displayName, authorId: user.id),
    );
    if (needsConfig) {
      await ref.read(clubConfigStatusProvider.notifier).refresh(force: true);
      reload();
    }
  }

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

  /// Récupère la configuration du club (délègue au statut observable).
  Future<ClubConfigOutcome> loadFromServer({bool force = false}) async {
    final outcome =
        await ref.read(clubConfigStatusProvider.notifier).refresh(force: force);
    reload();
    return outcome;
  }

  /// Déconnexion : la configuration reçue du club est oubliée.
  Future<void> forgetClubConfig() async {
    await ref.read(clubConfigStatusProvider.notifier).forget();
    reload();
  }
}
