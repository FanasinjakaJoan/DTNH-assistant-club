#!/usr/bin/env bash
# ============================================================================
#  DTNH Assistant Club — (Ré)génération des dossiers de plateforme
# ============================================================================
#  Les dossiers android/ et web/ sont DÉJÀ versionnés dans ce dépôt (épinglés
#  sur Flutter 3.44.9). Ce script sert à :
#    - ajouter iOS (non versionné, dépend de Xcode/macOS) ;
#    - régénérer une plateforme après une montée de version majeure de Flutter.
#
#  Usage :
#    bash scripts/setup_platforms.sh            # ajoute iOS
#    PLATFORMS=android,web bash scripts/setup_platforms.sh   # régénère (écrase !)
#
#  ⚠️ Régénérer android/ ou web/ écrase les personnalisations DTNH (manifest,
#     index.html, splash...). Préférer `git checkout app/android app/web` ensuite
#     pour restaurer la version du dépôt, ou ne régénérer que iOS.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/../app"

PLATFORMS="${PLATFORMS:-ios}"

echo "🏀 Génération des plateformes : $PLATFORMS"
flutter create --platforms="$PLATFORMS" \
  --org mg.dtnh \
  --project-name dtnh_assistant_club .
flutter pub get

echo "✅ Plateformes générées. Pensez à vérifier/appuyer les personnalisations DTNH."
