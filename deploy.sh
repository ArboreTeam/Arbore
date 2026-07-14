#!/usr/bin/env bash
#
# deploy.sh — Déploiement automatisé d'Arbore (backend + ai-generator + web) sur le VPS.
#
# Enchaîne :
#   1. git pull --ff-only
#   2. mongodump pre-deploy → backups/daily/arbore-predeploy-<ISO>.tar.gz
#   3. rotation des snapshots > 14 jours
#   4. docker compose build  (backend + ai-generator + web)
#   5. docker compose up -d  (backend + ai-generator + web)
#   6. health check backend (localhost:8080/health) + web (localhost:3000/)
#
# Codes de sortie :
#   0   succès
#   1   git pull, build, up, ou health check ont échoué
#   2   mongodump pre-deploy a échoué (refuse de continuer sans backup)
#   3   prérequis manquants (mongodump, docker, MONGODB_URI dans .env)
#
# À exécuter depuis la racine du dépôt sur le VPS, idéalement via SSH.
# Voir https://github.com/ArboreTeam/Arbore/issues/155 pour le contexte.
#

set -euo pipefail

# Couleurs ANSI (no-op si stdout n'est pas un terminal)
if [ -t 1 ]; then
    GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'
    RED='\033[0;31m'; NC='\033[0m'
else
    GREEN=''; BLUE=''; YELLOW=''; RED=''; NC=''
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SNAPSHOT_DIR="$SCRIPT_DIR/backups/daily"
SNAPSHOT_RETENTION_DAYS=14
DOCKER_COMPOSE=( sudo docker compose )

step() { printf '%b[%s/6]%b %s\n' "$YELLOW" "$1" "$NC" "$2"; }
ok()   { printf '%b✅ %s%b\n' "$GREEN" "$1" "$NC"; }
fail() { printf '%b❌ %s%b\n' "$RED" "$1" "$NC" >&2; }
warn() { printf '%b⚠️  %s%b\n' "$YELLOW" "$1" "$NC"; }

banner() {
    printf '%b========================================%b\n' "$BLUE" "$NC"
    printf '%b  Arbore — Déploiement Auto             %b\n' "$BLUE" "$NC"
    printf '%b========================================%b\n' "$BLUE" "$NC"
    echo
}

# ───── Prérequis ──────────────────────────────────────────────────
require_prereqs() {
    local missing=0
    if ! command -v mongodump >/dev/null 2>&1; then
        fail "mongodump introuvable — installe mongodb-database-tools"
        missing=1
    fi
    if ! command -v docker >/dev/null 2>&1; then
        fail "docker introuvable"
        missing=1
    fi
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        fail ".env manquant à la racine du dépôt"
        missing=1
    fi
    [ "$missing" -eq 0 ] || exit 3
}

# ───── [1/6] Git pull ─────────────────────────────────────────────
do_git_pull() {
    step 1 "Git pull..."
    if ! git pull --ff-only; then
        fail "Erreur lors du git pull"
        exit 1
    fi
    ok "Git pull réussi"
    echo
}

# ───── [2/6] Pre-deploy DB snapshot ───────────────────────────────
#
# Mongo Atlas M0 (tier gratuit) n'a pas de backup automatique. Ce
# mongodump local sert de filet de sécurité juste avant tout redémarrage
# du backend. La récupération est manuelle via mongorestore.
#
# Le dump et le tar tournent dans un tmpdir puis le résultat compressé
# est déplacé dans backups/daily/. Si l'une des étapes échoue, on abort
# pour ne pas déployer une nouvelle version sans filet.
do_db_snapshot() {
    step 2 "Pre-deploy DB snapshot..."

    local mongo_uri
    mongo_uri="$(grep '^MONGODB_URI=' "$SCRIPT_DIR/.env" | sed 's/^MONGODB_URI=//' || true)"
    if [ -z "$mongo_uri" ]; then
        fail "MONGODB_URI absente du .env — snapshot impossible"
        exit 3
    fi

    mkdir -p "$SNAPSHOT_DIR"
    local snapshot_name="arbore-predeploy-$(date -u +%Y-%m-%dT%H-%M-%SZ).tar.gz"
    local snapshot_path="$SNAPSHOT_DIR/$snapshot_name"
    local tmp_dump
    tmp_dump="$(mktemp -d)"

    # mongodump --quiet pour limiter les logs, sortie dans tmp_dump
    if ! mongodump --uri="$mongo_uri" --out="$tmp_dump" --quiet; then
        fail "mongodump a échoué — abort du deploy"
        rm -rf "$tmp_dump"
        exit 2
    fi

    if ! tar -czf "$snapshot_path" -C "$tmp_dump" .; then
        fail "Compression du dump a échoué — abort du deploy"
        rm -rf "$tmp_dump"
        rm -f "$snapshot_path"
        exit 2
    fi

    chmod 600 "$snapshot_path"
    rm -rf "$tmp_dump"

    local size
    size="$(du -h "$snapshot_path" | cut -f1)"
    ok "Snapshot : $snapshot_name ($size)"

    # Rotation des anciens snapshots
    local purged
    purged="$(find "$SNAPSHOT_DIR" -maxdepth 1 -name 'arbore-predeploy-*.tar.gz' \
              -type f -mtime "+$SNAPSHOT_RETENTION_DAYS" -print -delete | wc -l | tr -d ' ')"
    if [ "$purged" -gt 0 ]; then
        warn "Rotation : $purged snapshot(s) > ${SNAPSHOT_RETENTION_DAYS}j supprimé(s)"
    fi
    echo
}

# ───── [3/6] Docker compose build ─────────────────────────────────
do_docker_build() {
    local git_sha
    git_sha="$(git rev-parse HEAD)"
    step 3 "Docker compose build (commit ${git_sha:0:7})..."
    if ! "${DOCKER_COMPOSE[@]}" build backend ai-generator web; then
        fail "docker compose build a échoué"
        exit 1
    fi
    ok "Build réussi"
    echo
}

# ───── [4/6] Docker compose up ────────────────────────────────────
do_docker_up() {
    step 4 "Redémarrage des containers..."
    if ! "${DOCKER_COMPOSE[@]}" up -d backend ai-generator web; then
        fail "docker compose up a échoué"
        exit 1
    fi
    ok "Containers redémarrés"
    echo
}

# ───── [5/6] Logs de démarrage ────────────────────────────────────
do_show_logs() {
    step 5 "Logs de démarrage (10 dernières lignes)..."
    sleep 5
    "${DOCKER_COMPOSE[@]}" logs --tail 10 backend 2>&1 || true
    echo
}

# ───── [6/6] Health check ─────────────────────────────────────────
#
# Le backend expose /health en HTTP plain sur :8080 à ce stade
# (cf. issue #121 pour la migration HTTPS). Le check est bloquant :
# un health != 200 fait sortir en erreur pour signaler clairement
# qu'il faut intervenir.
# La route Community est elle aussi vérifiée : sans API key, elle doit exister
# et répondre 401. Un 404 révèle immédiatement une image backend obsolète.
check_community_route() {
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
        http://localhost:8080/api/v1/community/feed || true)"

    if [ "$code" = "401" ]; then
        ok "Community route registered (401 attendu sans API key)"
    else
        fail "Community route: HTTP ${code:-000} (401 attendu)"
        exit 1
    fi
}

# Check web non bloquant : le conteneur Next écoute sur :3000. Un échec n'arrête
# pas le déploiement (le routage reverse-proxy / Cloudflare peut être posé après).
check_web() {
    local code
    code="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:3000/ || echo "000")"
    if [ "$code" = "200" ]; then
        ok "Web health 200 OK"
    else
        warn "Web: HTTP $code sur :3000 (non bloquant — voir 'sudo docker logs --tail 50 arbore-web')"
    fi
}

do_health_check() {
    step 6 "Health check..."
    local attempts=0
    local max_attempts=10
    local http_code=""

    while [ "$attempts" -lt "$max_attempts" ]; do
        http_code="$(curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/health || echo "000")"
        if [ "$http_code" = "200" ]; then
            ok "Backend health 200 OK"
            check_community_route
            check_web
            echo
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 2
    done

    fail "Health: HTTP $http_code (après ${max_attempts} essais espacés de 2s)"
    fail "Vérifier les logs : sudo docker logs --tail 50 arbore-backend"
    exit 1
}

# ───── Footer ─────────────────────────────────────────────────────
footer() {
    printf '%b========================================%b\n' "$GREEN" "$NC"
    printf '%b  ✅ Déploiement terminé                %b\n' "$GREEN" "$NC"
    printf '%b========================================%b\n' "$GREEN" "$NC"
}

# ───── Main ───────────────────────────────────────────────────────
main() {
    banner
    require_prereqs
    do_git_pull
    do_db_snapshot
    do_docker_build
    do_docker_up
    do_show_logs
    do_health_check
    footer
}

main "$@"
