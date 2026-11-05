/// Détection des erreurs réseau « hors-ligne » de façon **compatible web**.
///
/// `dart:io` (et donc `SocketException`) n'existe pas sur le web : importer
/// `dart:io` directement casserait `flutter build web`. On utilise un import
/// conditionnel :
/// - natif / VM (tests) : `network_error_io.dart` reconnaît `SocketException` ;
/// - web : `network_error_stub.dart` (les erreurs réseau du navigateur
///   remontent déjà via `http.ClientException`, géré par le client).
export 'network_error_stub.dart'
    if (dart.library.io) 'network_error_io.dart';
