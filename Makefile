# ============================================================================
#  DTNH Assistant Club — raccourcis de build & prévisualisation
# ============================================================================
#  Usage : make <cible>   (ex. make web, make apk, make doctor)
# ============================================================================
.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help doctor get web chrome build-web pages-web apk apk-release apk-split \
        test analyze clean mockups setup-ios webhook-test

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

doctor: ## Vérifie Flutter 3.44+ / Dart 3.12+ et l'environnement
	@bash scripts/doctor.sh

get: ## flutter pub get
	@cd app && flutter pub get

web: ## Prévisualisation web headless (0.0.0.0:8080)
	@bash scripts/run_web.sh

chrome: ## Prévisualisation web dans Chrome (hot reload)
	@bash scripts/run_web.sh --chrome

build-web: ## Build web de production (base-href /)
	@bash scripts/build_web.sh

pages-web: ## Build web pour GitHub Pages (base-href /DTNH-assistant-club/)
	@BASE_HREF="/DTNH-assistant-club/" bash scripts/build_web.sh

apk: ## Build APK debug (installable, rapide)
	@bash scripts/build_apk.sh debug

apk-release: ## Build APK release (signé clé debug, installable)
	@bash scripts/build_apk.sh release

apk-split: ## Build APK release split-par-ABI (plus légers)
	@bash scripts/build_apk.sh split

test: ## Lance les tests Flutter
	@cd app && flutter test

analyze: ## Analyse statique (lints stricts)
	@cd app && flutter analyze

webhook-test: ## Tests Node du webhook Apps Script (sans dépendance)
	@node apps-script/test/webhook_test.mjs

mockups: ## Sert les maquettes HTML (aperçu rapide sans Flutter)
	@python3 docs/mockups/serve.py 8080

setup-ios: ## Génère le dossier iOS (macOS + Xcode requis)
	@bash scripts/setup_platforms.sh

clean: ## Nettoie les artefacts de build
	@cd app && flutter clean
	@rm -rf dist
