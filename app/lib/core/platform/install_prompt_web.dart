/// Implémentation **web** de la passerelle d'installation.
///
/// Utilise `dart:js_interop` (SDK Dart ≥ 3.3, donc largement disponible avec
/// Dart 3.12) : pas de `package:js` à ajouter au `pubspec`, et le code est
/// vérifié par le compilateur au lieu d'être une chaîne dynamique.
///
/// Contrat côté `web/index.html` :
/// - `window.dtnhInstall.detect()` → 'installed' | 'android' | 'ios' | 'desktop'
/// - `window.dtnhInstall.canPrompt()` → booléen
/// - `window.dtnhInstall.prompt()` → Promise<bool | null>
/// - `window.dtnhInstall.openUrl(url)` → ouvre un onglet
library;

import 'dart:js_interop';

/// Vue typée minimale de l'objet exposé par `web/index.html`.
@JS('dtnhInstall')
extension type _DtnhInstall._(JSObject _) implements JSObject {
  external JSString detect();
  external JSBoolean canPrompt();
  external JSPromise<JSAny?> prompt();
  external void openUrl(JSString url);
}

/// Accès à `window.dtnhInstall` (peut être `undefined` selon le contexte).
@JS('dtnhInstall')
external _DtnhInstall? get _installBridge;

/// `true` si le script d'amorçage PWA a bien exposé la passerelle.
bool get _isBridgeAvailable => _installBridge != null;

/// Contexte d'exécution renvoyé par le script embarqué.
String detectPlatformContext() {
  if (!_isBridgeAvailable) return 'desktop';
  try {
    return _installBridge!.detect().toDart;
  } catch (_) {
    return 'desktop';
  }
}

/// `true` si un prompt d'installation différé (`beforeinstallprompt`) est prêt.
bool canPromptInstall() {
  if (!_isBridgeAvailable) return false;
  try {
    return _installBridge!.canPrompt().toDart;
  } catch (_) {
    return false;
  }
}

/// Rejoue le prompt natif. Renvoie `null` en cas d'absence de prompt.
Future<bool?> requestInstall() async {
  if (!_isBridgeAvailable) return null;
  try {
    final result = await _installBridge!.prompt().toDart;
    // `null` side (navigateur sans prompt) ou booléen (choix utilisateur).
    if (result.isUndefinedOrNull || result.isNull) return null;
    return (result as JSBoolean).toDart;
  } catch (_) {
    return null;
  }
}

/// Ouvre une URL dans un nouvel onglet (téléchargement APK, documentation).
void openExternalUrl(String url) {
  if (!_isBridgeAvailable) return;
  try {
    _installBridge!.openUrl(url.toJS);
  } catch (_) {
    // Rien de critique : l'URL est aussi affichée en clair dans l'interface.
  }
}
