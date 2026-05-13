#!/usr/bin/env bash
#
# cleanup-test-db.sh — Nettoie la DB Mongo de test (`arbore_test`).
#
# À exécuter via cron sur le VPS, idéalement à un horaire de faible
# activité CI (04:00 UTC = 05:00/06:00 Paris). Le script vérifie qu'aucun
# workflow GitHub Actions n'est en cours avant de droper la DB, pour ne
# pas casser un run d'intégration en vol.
#
# La DB test est seedée à nouveau au prochain démarrage du backend grâce
# à seedTestDBPlantsIfEmpty() — pas besoin d'intervention manuelle pour
# retrouver le catalogue plantes.
#
# Variables d'environnement attendues :
#   MONGODB_URI_TEST       URI de connexion vers la DB test (`.env`)
#   GH_REPO                Slug du dépôt (default ArboreTeam/Arbore)
#   GH_TOKEN               Personal Access Token avec `repo` scope.
#                          Lecture via `gh api` si gh CLI installé.
#
# Codes de sortie :
#   0   succès (drop OK ou skip légitime)
#   1   prérequis manquant
#   2   appel API GitHub a échoué (CI status inconnu, on n'ose pas drop)
#   3   drop Mongo a échoué
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
GH_REPO="${GH_REPO:-ArboreTeam/Arbore}"

log() { printf '%s [cleanup-test-db] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }

# ── 1. Prérequis ──────────────────────────────────────────────────
if ! command -v mongosh >/dev/null 2>&1; then
    log "ERROR mongosh introuvable — installer mongodb-mongosh"
    exit 1
fi
if [ ! -f "$ENV_FILE" ]; then
    log "ERROR $ENV_FILE manquant"
    exit 1
fi

MONGODB_URI_TEST="$(grep '^MONGODB_URI_TEST=' "$ENV_FILE" | sed 's/^MONGODB_URI_TEST=//' || true)"
if [ -z "$MONGODB_URI_TEST" ]; then
    log "INFO MONGODB_URI_TEST non défini dans .env — rien à nettoyer, exit 0"
    exit 0
fi

# ── 2. Garde-fou : skip si une CI tourne ──────────────────────────
#
# On essaie dans l'ordre :
#   1. gh CLI (si installé ET authentifié)
#   2. curl + GH_TOKEN (si défini)
#   3. curl sans auth (le dépôt est public, l'API Actions est lisible
#      sans token — rate-limit 60 req/h largement suffisant pour un
#      cron quotidien)
# Si aucune option ne renvoie de réponse, on refuse de drop pour ne
# pas casser une CI en vol.

count_in_progress=""

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if count_in_progress=$(gh api "repos/$GH_REPO/actions/runs?status=in_progress" --jq '.total_count' 2>/dev/null); then
        log "INFO via gh CLI : $count_in_progress CI run(s) en cours"
    else
        count_in_progress=""
    fi
fi

if [ -z "$count_in_progress" ] && command -v curl >/dev/null 2>&1; then
    curl_args=(-fsS -H "Accept: application/vnd.github+json")
    if [ -n "${GH_TOKEN:-}" ]; then
        curl_args+=(-H "Authorization: Bearer $GH_TOKEN")
        via="REST (authenticated)"
    else
        via="REST (anonymous — repo public)"
    fi
    response=$(curl "${curl_args[@]}" "https://api.github.com/repos/$GH_REPO/actions/runs?status=in_progress" 2>/dev/null) || response=""
    if [ -n "$response" ]; then
        count_in_progress=$(echo "$response" | grep -oE '"total_count":[[:space:]]*[0-9]+' | head -1 | grep -oE '[0-9]+$' || echo "")
        if [ -n "$count_in_progress" ]; then
            log "INFO via $via : $count_in_progress CI run(s) en cours"
        fi
    fi
fi

if [ -z "$count_in_progress" ]; then
    log "ERROR impossible de vérifier le statut CI (gh + curl ont tous deux échoué), abort par sécurité"
    exit 2
fi

if [ "$count_in_progress" -gt 0 ]; then
    log "INFO $count_in_progress CI run(s) en cours, skip du cleanup"
    exit 0
fi

# ── 3. Drop arbore_test ───────────────────────────────────────────
log "INFO Drop de la DB arbore_test..."
if mongosh "$MONGODB_URI_TEST" --quiet --eval 'db.dropDatabase()'; then
    log "INFO Drop OK"
else
    log "ERROR drop a échoué"
    exit 3
fi

# ── 4. Restart backend pour réamorcer le catalogue plantes ────────
#
# seedTestDBPlantsIfEmpty() ne tourne qu'au démarrage du backend. Sans
# restart, les CI runs entre le drop et le prochain redémarrage
# trouveront plants vide → tests cassés. Restart pour réamorcer.
#
# Le container est piloté par docker-compose ; un simple restart suffit.
# Variable BACKEND_CONTAINER overridable si le nom change (default
# arbore-backend, défini dans docker-compose.yml).

BACKEND_CONTAINER="${BACKEND_CONTAINER:-arbore-backend}"

if command -v docker >/dev/null 2>&1 && sudo -n docker ps >/dev/null 2>&1; then
    if sudo -n docker restart "$BACKEND_CONTAINER" >/dev/null 2>&1; then
        log "INFO Backend container '$BACKEND_CONTAINER' restarted — seed plants amorcé"
    else
        log "WARN restart docker a échoué — la DB est dropée mais plants restera vide"
        log "WARN jusqu'au prochain restart manuel du backend"
    fi
else
    log "WARN docker indisponible ou sans accès sudo, skip du restart"
    log "WARN la DB est dropée mais plants restera vide jusqu'au prochain restart du backend"
fi
