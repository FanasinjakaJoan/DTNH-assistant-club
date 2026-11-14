import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../data/auth/auth_service.dart';
import '../../domain/entities/app_settings.dart';
import '../settings/settings_controller.dart';

/// État d'authentification exposé à l'interface.
class AuthState {
  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isConfigured = true,
  });

  /// Utilisateur connecté (`null` = session locale uniquement).
  final AuthUser? user;

  /// Une tentative de connexion / déconnexion est en cours.
  final bool isLoading;

  /// Dernier message d'erreur, effacé à la tentative suivante.
  final String? error;

  /// `false` si le build ne contient pas de configuration Supabase/Google.
  final bool isConfigured;

  bool get isSignedIn => user != null;

  bool get hasError => error != null;

  AuthState copyWith({
    AuthUser? user,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearUser = false,
    bool? isConfigured,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isConfigured: isConfigured ?? this.isConfigured,
    );
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService.instance);

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Orchestre la session Google et **alimente le mode local** de l'application.
///
/// Le reste de l'application ne dépend pas de Supabase : à la connexion, le
/// nom de l'utilisateur devient simplement l'auteur du pointage (traçabilité
/// déjà présente dans les colonnes `Auteur`). Si le serveur ne répond pas ou
/// si l'utilisateur préfère le mode local, tout continue de fonctionner
/// hors-ligne.
class AuthController extends Notifier<AuthState> {
  StreamSubscription<AuthUser?>? _subscription;

  AuthService get _service => ref.read(authServiceProvider);

  @override
  AuthState build() {
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      _subscription = null;
    });

    if (!_service.isReady) {
      return const AuthState(isConfigured: false);
    }

    final current = _service.currentUser;
    // Une session restaurée (rechargement de page web, réouverture de l'APK)
    // doit immédiatement réalimenter l'auteur du pointage.
    if (current != null) {
      Future<void>.microtask(() => _applyAuthor(current));
    }

    _subscription = _service.authStateChanges.listen(
      (user) {
        state = state.copyWith(
          user: user,
          clearUser: user == null,
          isLoading: false,
          clearError: true,
        );
        if (user != null) unawaited(_applyAuthor(user));
      },
      onError: (Object error) {
        debugPrint('Auth stream indisponible : $error');
      },
    );

    return AuthState(
      user: current,
      isConfigured: AppSettings.supportsGoogleAuth,
    );
  }

  /// Déclenche le consentement Google.
  Future<void> signInWithGoogle() async {
    if (!state.isConfigured) {
      state = state.copyWith(
        error: 'La connexion Google n\'est pas configurée dans cette version '
            'de l\'application.',
      );
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _service.signInWithGoogle();
      // Sur le web, la page est redirigée : l'état final arrive au rechargement
      // via le flux `onAuthStateChange`.
      state = state.copyWith(isLoading: false);
    } on AuthFailureException catch (error) {
      state = state.copyWith(isLoading: false, error: error.message);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Connexion Google impossible : $error',
      );
    }
  }

  /// Déconnexion : l'application repasse en mode local (aucune donnée perdue).
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _service.signOut();
      state = state.copyWith(isLoading: false, clearUser: true);
    } on AuthFailureException catch (error) {
      state = state.copyWith(isLoading: false, error: error.message);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Déconnexion impossible : $error',
      );
    }
  }

  void clearError() {
    if (state.hasError) state = state.copyWith(clearError: true);
  }

  /// Reporte le nom Google comme auteur du pointage (sans écraser un nom déjà
  /// saisi manuellement pour un autre utilisateur du même téléphone).
  Future<void> _applyAuthor(AuthUser user) async {
    final settings = ref.read(settingsProvider);
    if (settings.authorId == user.id) return;
    await ref.read(settingsProvider.notifier).setAuthenticatedAuthor(user);
  }
}
