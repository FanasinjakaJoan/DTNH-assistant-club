import 'package:flutter/foundation.dart' show kIsWeb;

import 'install_prompt_stub.dart'
    if (dart.library.js_interop) 'install_prompt_web.dart' as impl;

/// Environnement d'exécution détecté côté client.
enum InstallPlatform {
  /// Application installée (PWA standalone, APK Android, iOS).
  installed,

  /// Navigateur de bureau : pas d'installation possible via le prompt.
  desktopBrowser,

  /// Chrome / Edge / Samsung Internet sur Android : prompt natif disponible.
  androidBrowser,

  /// Safari iOS : installation manuelle par « Sur l'écran d'accueil ».
  iosBrowser,

  /// Application native (APK) : rien à installer.
  nativeApp,
}

/// Résultat d'une tentative d'installation.
enum InstallOutcome {
  /// L'utilisateur a accepté : l'app va s'installer.
  accepted,

  /// L'utilisateur a refusé le prompt natif.
  dismissed,

  /// Aucun prompt natif disponible : on affiche les instructions manuelles.
  manualInstructionsRequired,

  /// Rien à faire (déjà installée ou plateforme non éligible).
  unavailable,
}

/// Passerelle d'installation PWA, **sans package tiers**.
///
/// Le navigateur n'émet `beforeinstallprompt` qu'une seule fois, avant toute
/// interaction. L'événement est donc intercepté par un script inline de
/// `web/index.html`, qui l'expose via `window.dtnhInstall`. Ce fichier ne fait
/// que router les appels vers l'implémentation adaptée à la plateforme :
///
/// - web  → `install_prompt_web.dart` (`dart:js_interop`, choisi à la
///   compilation grâce à l'import conditionnel ci-dessus) ;
/// - natif → `install_prompt_stub.dart` (aucun accès à `dart:js_interop`, donc
///   l'APK Android compile sans dépendance web).
class InstallPrompt {
  const InstallPrompt._();

  /// Détecte la plateforme d'exécution.
  static Future<InstallPlatform> detect() async {
    if (!kIsWeb) return InstallPlatform.nativeApp;
    return switch (impl.detectPlatformContext()) {
      'installed' => InstallPlatform.installed,
      'android' => InstallPlatform.androidBrowser,
      'ios' => InstallPlatform.iosBrowser,
      _ => InstallPlatform.desktopBrowser,
    };
  }

  /// `true` si le navigateur a fourni un prompt d'installation différé.
  static Future<bool> canPrompt() async {
    if (!kIsWeb) return false;
    return impl.canPromptInstall();
  }

  /// Déclenche le prompt natif du navigateur (Chrome/Edge/Samsung).
  static Future<InstallOutcome> prompt() async {
    if (!kIsWeb) return InstallOutcome.unavailable;
    final accepted = await impl.requestInstall();
    if (accepted == null) return InstallOutcome.manualInstructionsRequired;
    return accepted ? InstallOutcome.accepted : InstallOutcome.dismissed;
  }

  /// Ouvre une URL dans un nouvel onglet (téléchargement de l'APK).
  static Future<void> openUrl(String url) async {
    if (!kIsWeb) return;
    impl.openExternalUrl(url);
  }
}
