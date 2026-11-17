import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../di/providers.dart';
import '../../domain/entities/sync_queue_item.dart';
import '../../domain/enums/sync_enums.dart';
import '../../sync/sync_engine.dart';
import '../../sync/sync_scheduler.dart';
import '../auth/auth_controller.dart';
import '../settings/settings_controller.dart';

/// État runtime de la synchronisation (volatile, non persisté).
class SyncRuntimeState {
  const SyncRuntimeState({
    this.isOnline = true,
    this.isSyncing = false,
    this.lastReport,
    this.lastError,
  });

  final bool isOnline;
  final bool isSyncing;
  final SyncReport? lastReport;
  final String? lastError;

  SyncRuntimeState copyWith({
    bool? isOnline,
    bool? isSyncing,
    SyncReport? lastReport,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncRuntimeState(
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      lastReport: lastReport ?? this.lastReport,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

final syncControllerProvider =
    NotifierProvider<SyncController, SyncRuntimeState>(SyncController.new);

/// Orchestrateur côté UI : écoute le réseau, déclenche les envois, expose l'état.
class SyncController extends Notifier<SyncRuntimeState>
    with WidgetsBindingObserver {
  SyncScheduler? _scheduler;
  bool _disposed = false;

  @override
  SyncRuntimeState build() {
    ref.onDispose(() {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      _scheduler?.dispose();
    });

    final scheduler = SyncScheduler(
      engine: ref.watch(syncEngineProvider),
      settings: ref.watch(settingsRepositoryProvider),
      // Chaque écriture en file déclenche un envoi automatique.
      queueChanges: ref.watch(syncQueueRepositoryProvider).watchCounters(),
    );

    scheduler
      ..onConnectivityChanged = (online) {
        if (_disposed) return;
        state = state.copyWith(isOnline: online);
      }
      ..onSyncingChanged = (syncing) {
        if (_disposed) return;
        state = state.copyWith(isSyncing: syncing);
      }
      ..onSyncCompleted = (report) {
        if (_disposed) return;
        state = state.copyWith(
          isSyncing: false,
          lastReport: report,
          lastError: report.error,
          clearError: report.error == null,
        );
        ref.read(settingsProvider.notifier).reload();
      }
      ..onSyncFailed = (error) {
        if (_disposed) return;
        state = state.copyWith(
          isSyncing: false,
          lastError: _messageOf(error),
        );
      };

    _scheduler = scheduler;
    WidgetsBinding.instance.addObserver(this);
    // Démarrage non bloquant : l'UI ne doit jamais attendre le réseau.
    Future<void>.microtask(scheduler.start);

    // Configuration du club : dès qu'une session Google existe (ou est
    // rétablie au rechargement d'une page web), l'URL et le secret de la cible
    // Sheets sont récupérés automatiquement. Aucune saisie n'est demandée.
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.isSignedIn && previous?.user?.id != next.user?.id) {
        _scheduleConfigRefresh();
      }
    }, fireImmediately: true);

    return const SyncRuntimeState();
  }

  /// Programme une récupération de configuration hors du cycle de `build`.
  ///
  /// Indispensable avec `fireImmediately` : sans ce report, la récupération
  /// écrirait dans `settingsProvider` pendant que Riverpod construit encore
  /// l'état initial.
  void _scheduleConfigRefresh({bool force = false}) {
    Future<void>.microtask(() => _refreshClubConfig(force: force));
  }

  /// Récupère (ou rafraîchit) la configuration du club sans bloquer l'UI.
  Future<void> _refreshClubConfig({bool force = false}) async {
    try {
      final settings = ref.read(settingsProvider.notifier);
      final outcome = await settings.loadFromServer(force: force);
      if (_disposed) return;
      // Une configuration récupérée peut débloquer des items en attente :
      // on relance un passage plutôt que d'attendre le filet périodique.
      if (outcome == ClubConfigOutcome.applied ||
          outcome == ClubConfigOutcome.appliedWithoutSheets) {
        final counters = await ref.read(syncQueueRepositoryProvider).counters();
        if (!_disposed && counters.outstanding > 0) {
          _scheduler?.triggerBackgroundSync();
        }
      }
    } catch (error) {
      debugPrint('Configuration du club indisponible : $error');
    }
  }

  /// Reprise au premier plan : les minuteurs ont pu être suspendus par le
  /// système pendant la veille, on relance donc un passage.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Une configuration jamais reçue (premier lancement hors-ligne) est
      // retentée ici : c'est le moment où le réseau est le plus probable.
      if (!ref.read(settingsProvider).isClubConfigFetched) {
        _scheduleConfigRefresh();
      }
      _scheduler?.onAppResumed();
    }
  }

  /// Recharge la configuration du club (bouton « Actualiser » des réglages).
  Future<ClubConfigOutcome> refreshClubConfig() async {
    final outcome =
        await ref.read(settingsProvider.notifier).loadFromServer(force: true);
    ref.read(settingsProvider.notifier).reload();
    return outcome;
  }

  /// Synchronisation manuelle (bouton « Synchroniser maintenant »).
  Future<SyncReport?> syncNow() async {
    final scheduler = _scheduler;
    if (scheduler == null) return null;
    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final report = await scheduler.syncNow();
      if (_disposed) return report;
      state = state.copyWith(
        isSyncing: false,
        lastReport: report,
        lastError: report.error,
        clearError: report.error == null,
      );
      ref.read(settingsProvider.notifier).reload();
      return report;
    } on AppException catch (error) {
      if (_disposed) return null;
      state = state.copyWith(isSyncing: false, lastError: error.message);
      return null;
    } catch (error) {
      if (_disposed) return null;
      state = state.copyWith(isSyncing: false, lastError: _messageOf(error));
      return null;
    }
  }

  /// Teste le webhook depuis les réglages ; renvoie le message serveur.
  Future<String> testConnection() async {
    // Si aucune URL n'est encore connue (appareil neuf, membre simplement
    // connecté), on tente d'abord de récupérer la configuration du club : sans
    // cela le test échouerait sur « URL invalide » alors que la connexion
    // Google suffit à tout configurer.
    if (!ref.read(settingsProvider).hasSyncTarget) {
      await _refreshClubConfig(force: true);
      if (!ref.read(settingsProvider).hasSyncTarget) {
        throw const SyncConfigurationException(
          'Aucune cible de synchronisation : connectez-vous avec Google '
          '(la configuration du club est alors récupérée automatiquement) ou '
          'renseignez une URL.',
        );
      }
    }
    final message = await ref.read(syncEngineProvider).testConnection();
    ref.read(settingsProvider.notifier).reload();
    return message;
  }

  Future<void> retryItem(String itemId) async {
    await ref.read(syncQueueRepositoryProvider).resetForRetry(itemId);
    await syncNow();
  }

  Future<void> retryAllErrors() async {
    final items =
        ref.read(syncQueueItemsProvider).valueOrNull ?? const <SyncQueueItem>[];
    for (final item in items) {
      if (item.status == SyncState.error) {
        await ref.read(syncQueueRepositoryProvider).resetForRetry(item.id);
      }
    }
    await syncNow();
  }

  /// Nettoie l'historique des envois réussis (garde la file légère).
  Future<void> clearHistory() =>
      ref.read(syncQueueRepositoryProvider).clearSynced();
}

String _messageOf(Object error) {
  if (error is AppException) return error.message;
  return 'Erreur inattendue : $error';
}
