import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../di/providers.dart';
import '../../domain/entities/sync_queue_item.dart';
import '../../domain/enums/sync_enums.dart';
import '../../sync/sync_engine.dart';
import '../../sync/sync_scheduler.dart';
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
class SyncController extends Notifier<SyncRuntimeState> {
  SyncScheduler? _scheduler;
  bool _disposed = false;

  @override
  SyncRuntimeState build() {
    ref.onDispose(() {
      _disposed = true;
      _scheduler?.dispose();
    });

    final scheduler = SyncScheduler(
      engine: ref.watch(syncEngineProvider),
      settings: ref.watch(settingsRepositoryProvider),
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
    // Démarrage non bloquant : l'UI ne doit jamais attendre le réseau.
    Future<void>.microtask(scheduler.start);

    return const SyncRuntimeState();
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
