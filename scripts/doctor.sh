#!/usr/bin/env bash
# ============================================================================
#  DTNH Assistant Club — Vérification des prérequis (Flutter 3.44+ / Dart 3.12+)
# ============================================================================
#  Usage :  bash scripts/doctor.sh
#  Sortie : code 0 si tout est OK, 1 sinon.
# ============================================================================
set -euo pipefail

MIN_FLUTTER="3.44.0"
MIN_DART="3.12.0"

# Retourne 0 si la version $1 est >= $2 (comparaison sémantique majeur.mineur.patch).
version_ge() {
  local a b
  a=$(printf '%s' "$1" | awk -F. '{printf "%d%03d%03d", $1+0, $2+0, $3+0}')
  b=$(printf '%s' "$2" | awk -F. '{printf "%d%03d%03d", $1+0, $2+0, $3+0}')
  [ "$a" -ge "$b" ]
}

echo "🏀 DTNH Assistant Club — diagnostic de l'environnement"
echo "------------------------------------------------------"

if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ Flutter introuvable dans le PATH."
  echo "   Installer Flutter >= $MIN_FLUTTER : https://docs.flutter.dev/get-started/install"
  exit 1
fi

JSON=$(flutter --version --machine 2>/dev/null || true)
FLUTTER_VERSION=$(printf '%s' "$JSON" | grep -o '"flutterVersion"[ ]*:[ ]*"[^"]*"' | cut -d'"' -f4)
DART_VERSION=$(printf '%s' "$JSON" | grep -o '"dartSdkVersion"[ ]*:[ ]*"[^"]*"' | cut -d'"' -f4)

STATUS=0

if [ -z "$FLUTTER_VERSION" ]; then
  echo "⚠️  Impossible de lire la version Flutter (flutter --version --machine)."
  STATUS=1
else
  if version_ge "$FLUTTER_VERSION" "$MIN_FLUTTER"; then
    echo "✅ Flutter $FLUTTER_VERSION (>= $MIN_FLUTTER)"
  else
    echo "❌ Flutter $FLUTTER_VERSION — version >= $MIN_FLUTTER requise."
    echo "   Mettre à jour : flutter upgrade  (ou flutter channel stable && flutter upgrade)"
    STATUS=1
  fi
fi

if [ -z "$DART_VERSION" ]; then
  echo "⚠️  Impossible de lire la version Dart."
else
  if version_ge "$DART_VERSION" "$MIN_DART"; then
    echo "✅ Dart $DART_VERSION (>= $MIN_DART)"
  else
    echo "❌ Dart $DART_VERSION — version >= $MIN_DART requise (livrée avec Flutter)."
    STATUS=1
  fi
fi

# Java est nécessaire uniquement pour compiler l'APK Android.
if command -v java >/dev/null 2>&1; then
  echo "✅ Java détecté : $(java -version 2>&1 | head -1)"
else
  echo "ℹ️  Java absent — requis seulement pour le build Android (APK)."
  echo "   Installer un JDK 17 : https://adoptium.net  (ou Android Studio)."
fi

echo "------------------------------------------------------"
echo "📋 flutter doctor détaillé :"
flutter doctor -v || true

exit "$STATUS"
