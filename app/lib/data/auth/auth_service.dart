import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';

/// Utilisateur authentifié, projeté sur les besoins de l'application.
///
/// Volontairement découplé de `supabase_flutter` : l'UI et les réglages ne
/// dépendent que de cette structure, ce qui permet de changer de fournisseur
/// d'identité (ou de revenir au mode local) sans toucher aux écrans.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.provider = 'google',
  });

  /// Identifiant Supabase (UUID) : sert de clé étrangère côté serveur.
  final String id;
  final String email;

  /// Nom affiché (Google `full_name`, sinon partie locale de l'email).
  final String displayName;

  final String? avatarUrl;

  /// Fournisseur d'identité (`google`, `email`...).
  final String provider;

  /// Initiales pour l'avatar de l'interface.
  String get initials {
    final words = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return (words.first.substring(0, 1) + words.last.substring(0, 1))
        .toUpperCase();
  }

  /// Reconstruit l'utilisateur à partir de la session Supabase.
  factory AuthUser.fromSupabaseUser(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final rawName = (metadata['full_name'] ??
            metadata['name'] ??
            metadata['user_name'])
        ?.toString()
        .trim();
    final email = user.email ?? '';
    final fallbackName =
        email.contains('@') ? email.split('@').first : (email.isEmpty ? 'Membre DTNH' : email);

    return AuthUser(
      id: user.id,
      email: email,
      displayName: (rawName == null || rawName.isEmpty) ? fallbackName : rawName,
      avatarUrl: (metadata['avatar_url'] ?? metadata['picture'])?.toString(),
      provider: user.appMetadata['provider']?.toString() ?? 'google',
    );
  }
}

/// Service d'authentification Google (délégué à Supabase Auth).
///
/// **Pourquoi Supabase Auth plutôt qu'un SDK Google direct** : le flux OAuth
/// (code + PKCE, validation du jeton, rotation des refresh tokens) est géré
/// côté serveur, l'application n'a aucun secret à stocker, et la session
/// obtenue pourra servir à durcir la RLS des tables `dtnh_*` (politique
/// `authenticated`). Un SDK Google direct obligerait à valider un id_token
/// nous-mêmes dans l'Edge Function.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  /// Message affiché quand le fournisseur Google est désactivé côté serveur.
  ///
  /// Partagé entre le pré-contrôle de [signInWithGoogle] et
  /// [_friendlyMessage] pour éviter toute divergence de formulation.
  static const String googleDisabledMessage =
      'La connexion Google n\'est pas encore activée sur le serveur. '
      'Un administrateur doit l\'activer dans le tableau de bord Supabase '
      '(Authentication > Providers > Google) avec le Client ID et le Client '
      'Secret créés dans Google Cloud Console.';

  /// Client HTTP injectable (tests).
  @visibleForTesting
  static http.Client httpClient = http.Client();

  /// `true` si le projet Supabase a pu être initialisé (clé présente).
  bool get isReady {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  SupabaseClient get _client => Supabase.instance.client;

  /// Interroge `/auth/v1/settings` pour savoir si un fournisseur est activé.
  ///
  /// Renvoie `true`/`false` si l'information a pu être lue, `null` en cas
  /// d'échec réseau ou de délai dépassé : dans ce dernier cas on laisse le flux
  /// OAuth se dérouler normalement (l'application reste utilisable hors-ligne).
  @visibleForTesting
  static Future<bool?> isProviderEnabled(
    String provider, {
    http.Client? client,
    String? supabaseUrl,
    String? anonKey,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final url = Uri.parse('${supabaseUrl ?? AppConfig.supabaseUrl}/auth/v1/settings');
    try {
      final response = await (client ?? httpClient)
          .get(
            url,
            headers: <String, String>{'apikey': anonKey ?? AppConfig.supabaseAnonKey},
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map) return null;
      final external = body['external'];
      if (external is! Map) return null;
      final value = external[provider];
      return value is bool ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// Utilisateur courant, ou `null` si non connecté.
  AuthUser? get currentUser {
    if (!isReady) return null;
    final user = _client.auth.currentUser;
    return user == null ? null : AuthUser.fromSupabaseUser(user);
  }

  /// Flux des changements de session (connexion, déconnexion, rafraîchissement).
  Stream<AuthUser?> get authStateChanges {
    if (!isReady) return const Stream<AuthUser?>.empty();
    return _client.auth.onAuthStateChange.map(
      (state) => state.session?.user == null
          ? null
          : AuthUser.fromSupabaseUser(state.session!.user),
    );
  }

  /// Lance le consentement Google dans le navigateur / l'écran natif.
  ///
  /// Sur le web, `signInWithOAuth` redirige la page ; au retour, l'URL contient
  /// les jetons et `Supabase.initialize` les consomme automatiquement. Sur
  /// Android, le retour se fait par le schéma profond déclaré dans le
  /// manifeste (`AppConfig.androidAuthCallbackScheme`).
  Future<void> signInWithGoogle() async {
    if (!isReady) {
      throw const AuthConfigurationException(
        'Authentification non configurée : la clé Supabase est absente du '
        'build.',
      );
    }

    // Pré-contrôle : Supabase répond `400 Unsupported provider: provider is not
    // enabled` tant que le fournisseur Google n'est pas activé dans le tableau
    // de bord. Sur le web, `signInWithOAuth` redirige la page vers cette
    // réponse JSON, ce qui remplace l'application et affiche l'erreur brute
    // « code 400 » à l'utilisateur. On interroge donc `/auth/v1/settings`
    // d'abord pour rester dans l'app et afficher un message actionnable.
    final googleEnabled = await AuthService.isProviderEnabled('google');
    if (googleEnabled == false) {
      throw const AuthConfigurationException(googleDisabledMessage);
    }

    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : '${AppConfig.androidAuthCallbackScheme}://login-callback',
        authScreenLaunchMode:
            kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        queryParams: const <String, String>{
          // Invite de compte : indispensable sur un téléphone partagé par le
          // staff (plusieurs coachs sur le même appareil).
          'prompt': 'select_account',
        },
      );
    } on AuthException catch (error) {
      throw AuthFailureException(_friendlyMessage(error.message));
    } catch (error) {
      throw AuthFailureException(
        'Connexion Google impossible : $error',
      );
    }
  }

  Future<void> signOut() async {
    if (!isReady) return;
    try {
      await _client.auth.signOut();
    } on AuthException catch (error) {
      throw AuthFailureException(_friendlyMessage(error.message));
    }
  }

  /// Message lisible en français pour les erreurs Supabase les plus courantes.
  String _friendlyMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('provider is not enabled') ||
        lower.contains('unsupported provider')) {
      return googleDisabledMessage;
    }
    if (lower.contains('redirect') && lower.contains('not allowed')) {
      return 'URL de retour non autorisée. Elle doit figurer dans les '
          '"Redirect URLs" de Supabase (Authentication > URL Configuration).';
    }
    if (lower.contains('popup') || lower.contains('cancelled')) {
      return 'Fenêtre de connexion fermée avant la fin du consentement.';
    }
    return raw;
  }
}
