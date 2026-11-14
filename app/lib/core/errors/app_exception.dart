/// Exceptions applicatives (jamais de `throw String` dans le code métier).
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  /// Message affichable à l'utilisateur (en français).
  final String message;

  /// Détail technique conservé pour les logs locaux.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Un champ obligatoire est vide ou invalide.
class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// Webhook non configuré ou secret manquant.
class SyncConfigurationException extends AppException {
  const SyncConfigurationException(super.message);
}

/// Le réseau est indisponible (Wi-Fi captif, DNS, timeout...).
class SyncOfflineException extends AppException {
  const SyncOfflineException(super.message);
}

/// Réponse HTTP non exploitable (5xx, 401, HTML inattendu...).
class SyncTransportException extends AppException {
  const SyncTransportException(
    super.message, {
    this.statusCode,
    this.isRetryable = true,
    super.cause,
  });

  final int? statusCode;
  final bool isRetryable;
}

/// Erreur de lecture/écriture du stockage local.
class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

/// Échec de la connexion Google / de la session Supabase.
class AuthFailureException extends AppException {
  const AuthFailureException(super.message, {super.cause});
}

/// Configuration d'authentification incomplète dans le build.
class AuthConfigurationException extends AppException {
  const AuthConfigurationException(super.message, {super.cause});
}
