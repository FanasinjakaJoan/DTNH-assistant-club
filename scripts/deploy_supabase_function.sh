#!/usr/bin/env bash
# ============================================================================
#  DTNH Assistant Club — déploiement de l'Edge Function `dtnh-sync`
# ============================================================================
#  Usage :
#     SUPABASE_ACCESS_TOKEN=sbp_xxx bash scripts/deploy_supabase_function.sh
#
#  Pourquoi ce script existe
#  -------------------------
#  La fonction `dtnh-sync` peut être « déployée » et pourtant répondre
#  systématiquement :
#      HTTP 503  {"code":"BOOT_ERROR","message":"Function failed to start"}
#  Ce n'est pas une erreur de code : le module est valide (`deno check` passe,
#  un lancement local répond 200). C'est un **déploiement incomplet** — la
#  fonction est enregistrée côté Supabase mais son bundle n'a pas été construit
#  (dépôt par l'éditeur en ligne interrompu, CLI absent du poste, ou secret
#  manquant au premier démarrage).
#
#  Ce script rend le déploiement reproductible et vérifie le résultat par un
#  vrai appel `ping` : on ne se contente pas d'un « deployed successfully ».
#
#  Variables d'environnement :
#     SUPABASE_ACCESS_TOKEN   (obligatoire) jeton personnel « sbp_... »
#                             https://supabase.com/dashboard/account/tokens
#     DTNH_SUPABASE_URL       (facultatif) défaut : projet DTNH
#     DTNH_SHARED_SECRET      (facultatif) secret partagé, si absent on saute
#                             le test ping authentifié
# ============================================================================
set -euo pipefail

FUNCTION_NAME="dtnh-sync"
SUPABASE_URL="${DTNH_SUPABASE_URL:-https://osjsczvsnyknkdwbciab.supabase.co}"
PROJECT_REF="${SUPABASE_URL#https://}"
PROJECT_REF="${PROJECT_REF%%.supabase.co}"

echo "🏀 Déploiement de l'Edge Function « $FUNCTION_NAME »"
echo "   Projet : $PROJECT_REF"
echo "------------------------------------------------------"

if [ -z "${SUPABASE_ACCESS_TOKEN:-}" ]; then
  echo "❌ SUPABASE_ACCESS_TOKEN manquant."
  echo "   Créer un jeton sur https://supabase.com/dashboard/account/tokens"
  echo "   puis relancer :  SUPABASE_ACCESS_TOKEN=sbp_... bash $0"
  exit 1
fi

if ! command -v supabase >/dev/null 2>&1; then
  echo "❌ Supabase CLI introuvable."
  echo "   Installation : https://supabase.com/docs/guides/cli"
  echo "   (macOS : brew install supabase/tap/supabase)"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FUNCTION_DIR="$REPO_ROOT/supabase/functions/$FUNCTION_NAME"

if [ ! -f "$FUNCTION_DIR/index.ts" ]; then
  echo "❌ $FUNCTION_DIR/index.ts introuvable."
  exit 1
fi

# 1. Le code est-il au moins valide avant de le pousser ?
if command -v deno >/dev/null 2>&1; then
  echo "🔎 Vérification du code (deno check)…"
  (cd "$FUNCTION_DIR" && deno check index.ts)
  echo "   ✅ code valide"
else
  echo "⚠️  deno introuvable : vérification locale ignorée."
fi

# 2. Déploiement. `--no-verify-jwt` est volontaire : la fonction s'authentifie
#    elle-même par le secret partagé (DTNH_SHARED_SECRET), et le client web
#    n'envoie pas de JWT Supabase sur ce chemin.
echo "🚀 Déploiement…"
supabase functions deploy "$FUNCTION_NAME" \
  --project-ref "$PROJECT_REF" \
  --no-verify-jwt

# 3. Vérification réelle : un `ping` doit répondre 200 et non BOOT_ERROR.
echo "🧪 Vérification (appel ping réel)…"
PING_BODY='{"action":"ping"'
if [ -n "${DTNH_SHARED_SECRET:-}" ]; then
  PING_BODY="$PING_BODY,\"secret\":\"$DTNH_SHARED_SECRET\""
fi
PING_BODY="$PING_BODY}"

HTTP_CODE=$(curl -sS -o /tmp/dtnh_ping.json -w '%{http_code}' \
  -X POST "$SUPABASE_URL/functions/v1/$FUNCTION_NAME" \
  -H 'content-type: application/json' \
  -d "$PING_BODY" || echo "000")

echo "   Réponse HTTP $HTTP_CODE"
cat /tmp/dtnh_ping.json 2>/dev/null | head -c 400
echo ""

if [ "$HTTP_CODE" = "503" ] && grep -q "BOOT_ERROR" /tmp/dtnh_ping.json 2>/dev/null; then
  echo "❌ La fonction répond encore BOOT_ERROR : le bundle n'a pas démarré."
  echo "   Vérifier les logs :  supabase functions logs $FUNCTION_NAME --project-ref $PROJECT_REF"
  exit 1
fi

if [ "$HTTP_CODE" != "200" ]; then
  echo "⚠️  Réponse inattendue ($HTTP_CODE). Vérifier les logs de la fonction :"
  echo "   supabase functions logs $FUNCTION_NAME --project-ref $PROJECT_REF"
  exit 1
fi

echo "✅ Fonction déployée et opérationnelle."
