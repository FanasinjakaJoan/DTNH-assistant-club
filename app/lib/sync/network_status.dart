import 'package:connectivity_plus/connectivity_plus.dart';

/// Abstraction de l'état réseau, consommée par le planificateur.
///
/// Elle existe pour découpler `SyncScheduler` du plugin `connectivity_plus` :
/// le planificateur devient testable sans canal de plateforme (un faux réseau
/// suffit), ce qui est indispensable pour vérifier les règles de déclenchement
/// de la synchronisation automatique.
abstract interface class NetworkStatus {
  /// `true` si au moins une interface réseau est disponible.
  Future<bool> checkOnline();

  /// Émet à chaque changement d'état réseau (`true` = en ligne).
  Stream<bool> get changes;
}

/// Implémentation réelle, adossée à `connectivity_plus`.
class ConnectivityNetworkStatus implements NetworkStatus {
  ConnectivityNetworkStatus([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> checkOnline() async {
    try {
      return _hasNetwork(await _connectivity.checkConnectivity());
    } catch (_) {
      // En cas de doute on tente : l'échec réseau est géré plus haut.
      return true;
    }
  }

  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_hasNetwork);

  static bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
