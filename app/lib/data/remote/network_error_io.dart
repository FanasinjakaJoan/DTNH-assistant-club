import 'dart:io';

/// Implémentation native (Android / iOS / VM de tests).
///
/// Une `SocketException` (DNS introuvable, réseau coupé, connexion refusée...)
/// signifie que l'appareil est hors-ligne : la sync sera retentée plus tard.
bool isOfflineError(Object error) => error is SocketException;

/// Message lisible extrait de l'erreur (sans le préfixe `SocketException:`).
String offlineErrorMessage(Object error) =>
    error is SocketException ? error.message : error.toString();
