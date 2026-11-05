import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../domain/repositories/settings_repository.dart';
import 'sync_engine.dart';

/// Surveille le réseau et déclenche la synchronisation automatique.
///
/// Stratégie « retour en ligne » : on ne synchronise pas à chaque paquet réseau
/// mais sur **transition hors-ligne -> en ligne**, avec un debounce de 3 s pour
/// laisser le Wi-Fi du gymnase finir sa négociation DHCP.
class SyncScheduler {
  SyncScheduler({
    required SyncEngine engine,
    required SettingsRepository settings,
    Connectivity? connectivity,
    this.debounce = const Duration(seconds: 3),
  })  : _engine = engine,
        _settings = settings,
        _connectivity = connectivity ?? Connectivity();

  final SyncEngine _engine;
  final SettingsRepository _settings;
  final Connectivity _connectivity;
  final Duration debounce;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _debounceTimer;
  bool _isOnline = true;
  bool _isRunning = false;

  bool get isOnline => _isOnline;

  /// Callbacks branchés sur l'UI (état réseau + compte-rendu).
  void Function(bool isOnline)? onConnectivityChanged;
  void Function(SyncReport report)? onSyncCompleted;
  void Function(Object error)? onSyncFailed;
  void Function(bool isSyncing)? onSyncingChanged;

  Future<void> start() async {
    _isOnline = await checkOnline();
    onConnectivityChanged?.call(_isOnline);

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final online = _hasNetwork(results);
      final wasOnline = _isOnline;
      _isOnline = online;
      onConnectivityChanged?.call(online);

      if (!wasOnline && online && _settings.current.autoSyncEnabled) {
        _scheduleSync();
      }
    });
  }

  /// Force un essai de synchronisation (bouton « Synchroniser maintenant »).
  Future<SyncReport> syncNow() async {
    _debounceTimer?.cancel();
    onSyncingChanged?.call(true);
    try {
      final report = await _engine.drain();
      onSyncCompleted?.call(report);
      return report;
    } catch (error) {
      onSyncFailed?.call(error);
      rethrow;
    } finally {
      onSyncingChanged?.call(false);
    }
  }

  Future<bool> checkOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _hasNetwork(results);
    } catch (_) {
      return true; // En cas de doute on tente : l'échec réseau est géré.
    }
  }

  /// Synchronisation silencieuse déclenchée par le retour du réseau.
  Future<void> triggerBackgroundSync() => _scheduleSync();

  void _scheduleSync() {
    if (_isRunning) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () async {
      if (_isRunning) return;
      _isRunning = true;
      onSyncingChanged?.call(true);
      try {
        final report = await _engine.drain(maxBatches: 4);
        onSyncCompleted?.call(report);
      } catch (error) {
        onSyncFailed?.call(error);
      } finally {
        _isRunning = false;
        onSyncingChanged?.call(false);
      }
    });
  }

  bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
  }
}
