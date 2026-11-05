#!/usr/bin/env bash
# ============================================================================
#  DTNH Assistant Club — Build Flutter Web pour Vercel
# ============================================================================
#  Vercel ne fournit pas Flutter dans son image de build : ce script installe
#  le SDK Flutter (épinglé) dans le conteneur, puis compile l'app web.
#  Appelé par vercel.json (buildCommand). Résultat : app/build/web/.
# ============================================================================
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.9}"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter}"

echo "==> Installation de Flutter $FLUTTER_VERSION dans $FLUTTER_HOME"
if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi
export PATH="$FLUTTER_HOME/bin:$PATH"

# Désactive analytics/animations pour un build CI non interactif.
flutter config --no-analytics >/dev/null 2>&1 || true
flutter --version

# Précharge uniquement les artefacts web (inutile de télécharger Android/iOS).
flutter precache --web

echo "==> flutter pub get"
cd app
flutter pub get

echo "==> flutter build web --release"
flutter build web --release --base-href "/" --pwa-strategy=offline-first

echo "==> Build terminé. Contenu de app/build/web :"
ls -la build/web | head -20
