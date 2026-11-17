import 'dart:async';

import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/sync_queue_repository.dart';
import 'network_status.dart';
import 'sync_engine.dart';

/// Surveille le réseau et déclenche la synchronisation automatique.
///
/// Quatre déclencheurs, pour qu'aucune donnée ne reste bloquée en local :
/// 1. **écriture locale** — une mise en file (pointage, paiement, joueur) est
///    suivie d'un envoi après un debounce court : le staff n'a rien à faire ;
/// 2. **retour en ligne** — transition hors-ligne -> en ligne, avec un debounce
///    de 3 s pour laisser le Wi-Fi du gymnase finir sa négociation DHCP ;
/// 3. **reprise de l'application** — un téléphone reste souvent en veille
///    plusieurs jours entre deux séances ; les minuteurs sont suspendus pendant
///    ce temps, donc on re-tente à chaque retour au premier plan ;
/// 4. **filet de sécurité périodique** — un minuteur en session (5 min par
///    défaut) rattrape le cas où le signal de connectivité n'a pas été émis
///    (changement d'antenne, portail captif déjà « connecté »).
///
/// Chaque déclencheur vérifie qu'il reste réellement des éléments à envoyer :
/// sans ce filtre, `lastSyncAt` avancerait à vide et deviendrait trompeur.
class SyncScheduler {
  SyncScheduler({
    required SyncEngine engine,
    required SettingsRepository settings,
    NetworkStatus? network,
    Stream<SyncQueueCounters>? queueChanges,
    this.debounce = const Duration(seconds: 3),
    this.writeDebounce = const Duration(seconds: 2),
    this.periodicInterval = const Duration(minutes: 5),
    this.enablePeriodic = true,
  })  : _engine = engine,
        _settings = settings,
        _network = network ?? ConnectivityNetworkStatus(),
        _queueChanges = queueChanges;

  final SyncEngine _engine;
  final SettingsRepository _settings;
  final NetworkStatus _network;

  /// Flux émis à chaque écriture dans la file (null = déclencheur désactivé).
  final Stream<SyncQueueCounters>? _queueChanges;
  final Duration debounce;

  /// Délai après une écriture locale : assez court pour que le staff voie la
  /// donnée partir, assez long pour regrouper un pointage de 15 joueurs en un
  /// seul lot (chaque joueur génère une écriture distincte).
  final Duration writeDebounce;

  /// Intervalle du filet de sécurité en session (0 = désactivé).
  final Duration periodicInterval;
  final bool enablePeriodic;

  StreamSubscription<bool>? _subscription;
  StreamSubscription<SyncQueueCounters>? _queueSubscription;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  bool _isOnline = true;
  bool _isRunning = false;

  /// Un déclenchement demandé pendant un envoi en cours est mémorisé au lieu
  /// d'être perdu : c'est ce qui garantit qu'une donnée saisie pendant la
  /// synchronisation précédente finit bien par partir.
  bool _resyncRequested = false;
  bool _disposed = false;

  bool get isOnline => _isOnline;

  /// Callbacks branchés sur l'UI (état réseau + compte-rendu).
  void Function(bool isOnline)? onConnectivityChanged;
  void Function(SyncReport report)? onSyncCompleted;
  void Function(Object error)? onSyncFailed;
  void Function(bool isSyncing)? onSyncingChanged;

  Future<void> start() async {
    _isOnline = await _network.checkOnline();
    onConnectivityChanged?.call(_isOnline);

    _subscription = _network.changes.listen((online) {
      final wasOnline = _isOnline;
      _isOnline = online;
      onConnectivityChanged?.call(online);

      if (!wasOnline && online) {
        _scheduleAuto();
      }
    });

    // Chaque écriture dans la file déclenche un envoi : c'est ce qui rend la
    // synchronisation invisible pour le staff (aucun bouton à presser).
    _queueSubscription = _queueChanges?.listen((counters) {
      if (counters.outstanding > 0) {
        _scheduleAuto(write: true);
      }
    });

    if (enablePeriodic && periodicInterval > Duration.zero) {
      _periodicTimer = Timer.periodic(periodicInterval, (_) {
        _scheduleAuto();
      });
    }

    // Un premier passage au démarrage : l'application peut avoir été fermée
    // avec des éléments encore en attente (pointage de la veille hors-ligne).
    _scheduleAuto();
  }

  /// À appeler quand l'application revient au premier plan.
  void onAppResumed() {
    _scheduleAuto();
  }

  /// Force un essai de synchronisation (bouton « Synchroniser maintenant »).
  Future<SyncReport> syncNow() async {
    _debounceTimer?.cancel();
    _resyncRequested = false;
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
    _isOnline = await _network.checkOnline();
    return _isOnline;
  }

  /// Synchronisation silencieuse (retour réseau, reprise, minuteur).
  Future<void> triggerBackgroundSync() async {
    _scheduleAuto();
  }

  /// Déclenche si — et seulement si — la synchronisation automatique est
  /// activée, l'appareil en ligne et la file non vide.
  ///
  /// [write] sélectionne le debounce court : une écriture locale doit partir
  /// vite (retour visuel pour le staff), alors qu'un retour réseau peut
  /// attendre la fin de la négociation Wi-Fi.
  void _scheduleAuto({bool write = false}) {
    if (_disposed) return;
    if (!_settings.current.autoSyncEnabled) return;
    if (!_isOnline) return;

    // La vérification de la file est asynchrone : on laisse le soin à
    // `_runScheduled` de l'ignorer si elle est vide entre-temps.
    _scheduleSync(write: write);
  }

  void _scheduleSync({bool write = false}) {
    if (_disposed) return;
    if (_isRunning) {
      // Un envoi est en cours : on note qu'un nouveau passage est nécessaire.
      _resyncRequested = true;
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(write ? writeDebounce : debounce, _runScheduled);
  }

  Future<void> _runScheduled() async {
    if (_disposed || _isRunning) return;
    _isRunning = true;
    _resyncRequested = false;
    onSyncingChanged?.call(true);
    try {
      if (await _engine.hasOutstanding()) {
        final report = await _engine.drain(maxBatches: 4);
        onSyncCompleted?.call(report);
      }
    } catch (error) {
      onSyncFailed?.call(error);
    } finally {
      _isRunning = false;
      onSyncingChanged?.call(false);
      // Des données sont arrivées pendant l'envoi : on repart pour un tour.
      if (_resyncRequested && !_disposed) {
        _scheduleSync();
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _debounceTimer = null;
    _periodicTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _queueSubscription?.cancel();
    _queueSubscription = null;
  }
}
