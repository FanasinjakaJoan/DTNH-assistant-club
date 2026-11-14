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
  /// le refresh token à la main.
  Future<String?> currentAccessToken() async {
    if (!isAvailable) return null;
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;
    if (token == null || token.isEmpty) return null;
    return token;
  }
}
