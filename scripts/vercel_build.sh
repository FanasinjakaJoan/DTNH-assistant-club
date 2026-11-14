#!/usr/bin/env bash
# ============================================================================
#  DTNH Assistant Club — Build Flutter Web pour Vercel
# ============================================================================
#  Vercel ne fournit pas Flutter dans son image de build : ce script installe
#  le SDK Flutter (épinglé) dans le conteneur, puis compile l'app web.
#  Appelé par vercel.json (buildCommand). Résultat : app/build/web/.
#
#  Variables d'environnement (facultatives, valeurs par défaut en dur dans
#  app/lib/core/config/app_config.dart) :
#    DTNH_SUPABASE_SYNC_URL  URL de l'Edge Function dtnh-sync
#    DTNH_SUPABASE_SECRET    secret partagé de la fonction
#    DTNH_APK_URL            page de téléchargement de l'APK
#    DTNH_WEB_URL            URL publique de l'application
#    DTNH_SUPABASE_URL       URL du projet Supabase (Auth)
#    DTNH_SUPABASE_ANON_KEY  clé publishable (protégée par la RLS)
#    DTNH_GOOGLE_CLIENT_ID   client ID OAuth Google (documentaire)
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

# Valeurs injectées au build (--dart-define). On ne transmet que celles qui
# sont réellement fournies par l'environnement Vercel : sinon les valeurs par
# défaut compilées dans AppConfig restent utilisées.
#
# Note : on utilise des blocs `if` et non `[ ... ] && ...`, car avec
# `set -e` un test faux interromprait le script.
DART_DEFINES=()
if [ -n "${DTNH_SUPABASE_SYNC_URL:-}" ]; then
  DART_DEFINES+=("--dart-define=DTNH_SUPABASE_SYNC_URL=${DTNH_SUPABASE_SYNC_URL}")
fi
if [ -n "${DTNH_SUPABASE_SECRET:-}" ]; then
  DART_DEFINES+=("--dart-define=DTNH_SUPABASE_SECRET=${DTNH_SUPABASE_SECRET}")
fi
if [ -n "${DTNH_APK_URL:-}" ]; then
  DART_DEFINES+=("--dart-define=DTNH_APK_URL=${DTNH_APK_URL}")
fi
if [ -n "${DTNH_WEB_URL:-}" ]; then
  DART_DEFINES+=("--dart-define=DTNH_WEB_URL=${DTNH_WEB_URL}")
fi
if [ -n "${DTNH_SUPABASE_URL:-}" ]; then
  DART_DEFINES+=("--dart-define=DTNH_SUPABASE_URL=${DTNH_SUPABASE_URL}")
fi
if [ -n "${DTNH_SUPABASE_ANON_KEY:-}" ]; then
  DART_DEFINES+=("--dart-define=DTNH_SUPABASE_ANON_KEY=${DTNH_SUPABASE_ANON_KEY}")
fi
if [ -n "${DTNH_GOOGLE_CLIENT_ID:-}" ]; then
  DART_DEFINES+=("--dart-define=DTNH_GOOGLE_CLIENT_ID=${DTNH_GOOGLE_CLIENT_ID}")
fi

echo "==> flutter build web --release (${#DART_DEFINES[@]} dart-define)"
if [ "${#DART_DEFINES[@]}" -gt 0 ]; then
  flutter build web --release \
    --base-href "/" \
    --pwa-strategy=offline-first \
    "${DART_DEFINES[@]}"
else
  flutter build web --release --base-href "/" --pwa-strategy=offline-first
fi

echo "==> Build terminé. Contenu de app/build/web :"
ls -la build/web | head -20
