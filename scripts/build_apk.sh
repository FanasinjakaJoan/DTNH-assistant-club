#!/usr/bin/env bash
# ============================================================================
#  DTNH Assistant Club — Build APK Android (distribution interne)
# ============================================================================
#  Usage :
#    bash scripts/build_apk.sh             # debug (rapide, installable)
#    bash scripts/build_apk.sh release     # release (signé clé debug, installable)
#    bash scripts/build_apk.sh split       # release split-par-ABI (APK plus légers)
#
#  Résultat : dist/dtnh-assistant-v<version>-<mode>.apk
#  L'APK release est signé avec la clé debug (voir android/app/build.gradle.kts) :
#  il est immédiatement installable par le staff, sans keystore à gérer.
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app"

MODE="${1:-debug}"
VERSION=$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[ ]*//; s/+.*//')
VERSION="${VERSION:-0.0.0}"

echo "🏀 Build APK DTNH — mode '$MODE', version $VERSION"
flutter pub get

case "$MODE" in
  debug)
    flutter build apk --debug
    SRC="build/app/outputs/flutter-apk/app-debug.apk"
    ;;
  release)
    flutter build apk --release
    SRC="build/app/outputs/flutter-apk/app-release.apk"
    ;;
  split)
    flutter build apk --release --split-per-abi
    SRC="build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
    ;;
  *)
    echo "❌ Mode inconnu : '$MODE' (attendu : debug | release | split)"
    exit 2
    ;;
esac

mkdir -p "$ROOT/dist"
if [ "$MODE" = "split" ]; then
  # Copie tous les APK par ABI.
  for apk in build/app/outputs/flutter-apk/*-release.apk; do
    base=$(basename "$apk" .apk)
    cp "$apk" "$ROOT/dist/dtnh-assistant-v$VERSION-$base.apk"
  done
  echo "✅ APK split copiés dans dist/ :"
  ls -lh "$ROOT/dist/"*"$VERSION"*release.apk
else
  DEST="$ROOT/dist/dtnh-assistant-v$VERSION-$MODE.apk"
  cp "$SRC" "$DEST"
  echo "✅ APK prêt : $DEST"
  ls -lh "$DEST"
fi

echo ""
echo "📲 Installer sur un téléphone :  adb install -r \"$DEST\""
echo "   (ou transférer le fichier .apk et l'ouvrir sur l'appareil)"
