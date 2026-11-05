#!/usr/bin/env bash
# ============================================================================
#  DTNH Assistant Club — Build Web de production (PWA offline-first)
# ============================================================================
#  Usage :
#    bash scripts/build_web.sh                       # base-href "/" (Vercel/Firebase)
#    BASE_HREF="/DTNH-assistant-club/" bash scripts/build_web.sh   # GitHub Pages
#
#  Résultat : app/build/web/  (prêt à héberger)
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app"

BASE_HREF="${BASE_HREF:-/}"

echo "🏀 Build Web DTNH — base-href='$BASE_HREF'"
flutter pub get
flutter build web --release \
  --base-href "$BASE_HREF" \
  --pwa-strategy=offline-first

# Config Vercel prête à l'emploi pour un déploiement statique du dossier build/web.
if [ -f "$ROOT/config/vercel.json" ]; then
  cp "$ROOT/config/vercel.json" build/web/vercel.json
  echo "📝 config/vercel.json copiée dans build/web/ (déploiement Vercel statique)."
fi

echo ""
echo "✅ Build Web terminé : app/build/web/"
du -sh build/web 2>/dev/null || true
echo ""
echo "Tester en local :  python3 -m http.server 8090 --directory build/web"
echo "Déployer :         voir docs/05-DEVOPS.md (GitHub Pages / Vercel / Firebase)"
