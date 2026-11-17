import 'package:supabase_flutter/supabase_flutter.dart';

/// Accès **minimal et isolé** au jeton de la session Supabase.
///
/// Le client de synchronisation (`AppsScriptClient`) ne dépend pas de
/// `supabase_flutter` : il reçoit seulement une fonction `Future<String?>`
/// capable de fournir un JWT. Cette indirection permet
///
/// 1. de compiler et de tester le moteur de sync **sans** session ouverte ;
/// 2. de basculer plus tard sur un autre fournisseur d'identité sans toucher
///    au transport ;
/// 3. de rester hors-ligne : si Supabase n'est pas initialisé (bundle sans
///    clé, démarrage hors réseau), la fonction renvoie `null` et la
///    synchronisation retombe proprement sur le secret partagé.
class AuthTokenSource {
  const AuthTokenSource();

  /// Avance sur l'expiration : on rafraîchit le jeton s'il expire dans moins
  /// de 2 minutes. Un envoi peut durer 30 s ; sans cette marge, un jeton valide
  /// au départ pouvait expirer pendant le transport et produire un 401 alors
  /// que la session Google était parfaitement utilisable.
  static const Duration refreshMargin = Duration(minutes: 2);

  /// Vrai si un client Supabase est disponible dans ce build.
  static bool get isAvailable {
    try {
      Supabase.instance;
      return true;
    } on Object {
      return false;
    }
  }

  /// JWT de l'utilisateur connecté, ou `null` en mode hors-ligne.
  ///
  /// Le SDK rafraîchit automatiquement le jeton expiré : on ne manipule jamais
  /// le refresh token à la main. On force simplement un rafraîchissement quand
  /// le jeton est sur le point d'expirer — sinon l'appel partait avec un jeton
  /// mort et l'Edge Function répondait `401`, ce qui ressemblait à tort à un
  /// « secret invalide » pour le staff.
  Future<String?> currentAccessToken() async {
    if (!isAvailable) return null;
    final auth = Supabase.instance.client.auth;
    var session = auth.currentSession;
    if (session == null) return null;

    if (_isNearExpiry(session)) {
      try {
        final refreshed = await auth.refreshSession();
        if (refreshed.session != null) session = refreshed.session;
      } on Object {
        // Réseau coupé : on tente quand même avec le jeton courant (il peut
        // encore être valide) ; un échec 401 restera réessayable.
      }
    }

    final token = session?.accessToken;
    if (token == null || token.isEmpty) return null;
    return token;
  }

  bool _isNearExpiry(Session session) {
    final expiresAt = session.expiresAt;
    if (expiresAt == null) return false;
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    return DateTime.now().add(refreshMargin).isAfter(expiry);
  }
}
