/// Implémentation web : `dart:io` n'est pas disponible.
///
/// Sur le web, une coupure réseau se manifeste par une `http.ClientException`
/// (déjà interceptée par `AppsScriptClient`), jamais par une `SocketException`.
/// Il n'y a donc rien de spécifique à détecter ici.
bool isOfflineError(Object error) => false;

/// Message générique (jamais utilisé pour une `SocketException` sur le web).
String offlineErrorMessage(Object error) => error.toString();
