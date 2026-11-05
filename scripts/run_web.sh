#!/usr/bin/env bash
# ============================================================================
#  DTNH Assistant Club — Prévisualisation locale Web (offline-first)
# ============================================================================
#  Usage :
#    bash scripts/run_web.sh             # serveur web headless (0.0.0.0:8080)
#    bash scripts/run_web.sh --chrome    # ouvre Chrome avec hot reload
#    PORT=9000 bash scripts/run_web.sh   # autre port
#
#  Offline / CORS :
#   - Le stockage local (Hive) utilise IndexedDB sur le web : c'est du
#     SAME-ORIGIN, donc AUCUNE restriction CORS sur les données locales.
#   - Le seul appel cross-origin est le webhook Google Apps Script. Il est
#     envoyé en `text/plain` sur le web (voir apps_script_client.dart) pour
#     éviter le préflight OPTIONS qu'Apps Script ne gère pas. Aucun bypass
#     de sécurité navigateur n'est nécessaire.
#   - Une fois chargée, l'app fonctionne hors-ligne (PWA + service worker).
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/../app"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
DEVICE="web-server"
if [ "${1:-}" = "--chrome" ]; then
  DEVICE="chrome"
fi

echo "🏀 DTNH Assistant Club — démarrage web ($DEVICE)"
flutter pub get

if [ "$DEVICE" = "chrome" ]; then
  echo "🌐 Chrome : http://localhost:$PORT"
  exec flutter run -d chrome --web-port "$PORT"
else
  echo "🌐 Serveur web : http://$HOST:$PORT  (ouvrez cette URL dans un navigateur)"
  echo "   (Ctrl+C pour arrêter)"
  exec flutter run -d web-server --web-hostname "$HOST" --web-port "$PORT"
fi
