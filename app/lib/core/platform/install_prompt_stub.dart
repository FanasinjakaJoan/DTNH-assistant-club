/// Implémentation **non-web** de la passerelle d'installation.
///
/// Compilée pour Android/iOS : elle n'importe évidemment pas `dart:js_interop`
/// (indisponible hors navigateur). L'application native est déjà « installée »,
/// ces fonctions ne sont donc jamais sollicitées depuis l'UI.
library;

/// Contexte d'exécution : seul `native` est possible ici.
String detectPlatformContext() => 'native';

/// Aucun prompt d'installation : la distribution passe par l'APK.
bool canPromptInstall() => false;

/// Aucune installation navigateur disponible.
Future<bool?> requestInstall() async => null;

/// Sans navigateur, l'ouverture d'URL est gérée par l'OS : no-op volontaire.
void openExternalUrl(String url) {}
