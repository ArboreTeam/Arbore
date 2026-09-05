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

# Empreinte du script avant tout pull, pour détecter qu'il s'est mis à jour
# lui-même (cf. do_git_pull).
SELF_SHA_BEFORE_PULL="$(sha256sum "$0" 2>/dev/null | cut -d" " -f1 || echo unknown)"

# Arguments du script capturés au niveau global : `do_git_pull` est appelée
# sans paramètres, donc `$@` y serait vide et la ré-exécution les perdrait.
SCRIPT_ARGS=("$@")

SNAPSHOT_DIR="$SCRIPT_DIR/backups/daily"
SNAPSHOT_RETENTION_DAYS=14
# Préfixe de privilège isolé du reste de la commande : il faut pouvoir insérer
# une assignation de variable APRÈS `sudo`, car sudo réinitialise
# l'environnement — un préfixe `VAR=val sudo …` est silencieusement perdu
# (vérifié sur le VPS). Vider ce tableau suffit si docker tourne sans sudo.
DOCKER_PRIVILEGE=( sudo )
DOCKER_COMPOSE=( "${DOCKER_PRIVILEGE[@]}" docker compose )

step() { printf '%b[%s/7]%b %s\n' "$YELLOW" "$1" "$NC" "$2"; }
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

# ───── [1/7] Git pull ─────────────────────────────────────────────
#
# Données hors bande : fichiers que git suit encore (ils ont été committés avant
# que la règle `.gitignore` n'existe) mais qui sont en réalité gérés directement
# sur le serveur — les modèles 3D sont regénérés et nettoyés en place.
#
# Historiquement le garde-fou refusait tout checkout non vierge. Comme ces
# fichiers sont modifiés en permanence, `deploy.sh` était inutilisable en
# pratique : les déploiements le contournaient à la main, et sautaient donc le
# `mongodump` pre-deploy — le seul filet de sécurité, Atlas M0 n'ayant aucun
# backup automatique. Le garde-fou distingue maintenant les modifications de
# code (bloquantes) des données hors bande (attendues). Cf. #341.
OUT_OF_BAND_PATHS=( "ArboreBackend/models/" )

# is_out_of_band <chemin> — vrai si le chemin est sous un préfixe hors bande.
is_out_of_band() {
    local path="$1" prefix
    for prefix in "${OUT_OF_BAND_PATHS[@]}"; do
        case "$path" in "$prefix"*) return 0 ;; esac
    done
    return 1
}

do_git_pull() {
    step 1 "Git pull..."

    # Trois catégories, traitées différemment :
    #   - fichier SUIVI modifié hors données hors bande  → bloquant (du code)
    #   - fichier SUIVI modifié sous un chemin hors bande → toléré, signalé
    #   - fichier NON SUIVI                              → toléré, signalé
    #     (un fichier non suivi ne peut pas faire échouer un fast-forward)
    local blocking=() out_of_band=0 untracked=0
    local line entry_status entry_path
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        entry_status="${line:0:2}"
        entry_path="${line:3}"
        # Un renommage s'écrit « ancien -> nouveau » : seule la destination compte.
        # À faire AVANT de retirer les guillemets, sinon celui qui ouvre la
        # destination survit et le préfixe hors bande n'est plus reconnu.
        case "$entry_status" in R*) entry_path="${entry_path##* -> }" ;; esac
        # git entoure de guillemets les chemins contenant des espaces.
        entry_path="${entry_path%\"}"
        entry_path="${entry_path#\"}"

        if [ "$entry_status" = "??" ]; then
            untracked=$((untracked + 1))
        elif is_out_of_band "$entry_path"; then
            out_of_band=$((out_of_band + 1))
        else
            blocking+=("$entry_status $entry_path")
        fi
    done < <(git status --porcelain)

    if [ "${#blocking[@]}" -gt 0 ]; then
        fail "Le checkout contient des modifications de fichiers suivis — déploiement refusé"
        printf '     %s\n' "${blocking[@]}" >&2
        fail "Committer ou annuler ces changements avant de déployer"
        exit 1
    fi

    # `if` explicite plutôt que `[ ... ] && warn ...` : sous `set -e`, un test
    # faux en fin de fonction ferait sortir le script.
    if [ "$out_of_band" -gt 0 ]; then
        warn "$out_of_band fichier(s) de données hors bande modifiés (${OUT_OF_BAND_PATHS[*]}) — ignorés, gérés hors git"
    fi
    if [ "$untracked" -gt 0 ]; then
        warn "$untracked fichier(s) non suivis présents — ignorés (sans effet sur un fast-forward)"
    fi

    if ! git pull --ff-only; then
        fail "Erreur lors du git pull"
        if [ "$out_of_band" -gt 0 ]; then
            fail "Si un commit entrant touche ${OUT_OF_BAND_PATHS[*]}, git refuse d'écraser les"
            fail "modifications locales : sauvegarder ces fichiers puis les restaurer après le pull"
        fi
        exit 1
    fi
    ok "Git pull réussi"

    # Le script vient peut-être de se remplacer lui-même. bash lit le fichier
    # au fil de l'exécution : sans ré-exécution, on continuerait avec l'ANCIENNE
    # version, et toute modification de deploy.sh ne prendrait effet qu'au
    # déploiement SUIVANT. Constaté en production le 2026-09-05 — l'étape
    # `ops/` nouvellement ajoutée n'avait pas tourné, et rien ne le signalait
    # hormis les libellés « [2/6] » au lieu de « [2/7] ».
    #
    # ARBORE_DEPLOY_REEXECED garde contre une boucle : après ré-exécution, le
    # script ne se relance pas une seconde fois.
    if [ -z "${ARBORE_DEPLOY_REEXECED:-}" ]; then
        local after
        after="$(sha256sum "$0" 2>/dev/null | cut -d" " -f1 || true)"
        if [ -n "$after" ] && [ "$after" != "$SELF_SHA_BEFORE_PULL" ]; then
            warn "deploy.sh a été mis à jour par le pull — ré-exécution avec la nouvelle version"
            echo
            export ARBORE_DEPLOY_REEXECED=1
            # Forme `${x[@]+...}` : sans elle, un tableau vide déclencherait
            # « unbound variable » sous `set -u`.
            exec "$0" ${SCRIPT_ARGS[@]+"${SCRIPT_ARGS[@]}"}
        fi
    fi
    echo
}

# ───── [2/7] Configuration système déclarative ────────────────────
#
# `ops/` est la source de vérité de tout ce qui vit hors des conteneurs :
# entrées cron, unités systemd, scripts privilégiés. Cette étape les
# applique à CHAQUE déploiement, de façon idempotente.
#
# Pourquoi : ces éléments étaient auparavant posés à la main en suivant un
# runbook, donc invisibles au dépôt et impossibles à vérifier. La doc a
# dérivé sans que personne ne le voie — elle a décrit un seul cron pendant
# des mois alors que la machine en avait deux (#393, #400, #401).
#
# Conséquence assumée : une modification faite à la main sur la machine est
# ÉCRASÉE au déploiement suivant. C'est le comportement voulu — le dépôt
# fait autorité.
do_apply_ops() {
    step 2 "Configuration système (ops/)..."

    if [ ! -d "$SCRIPT_DIR/ops" ]; then
        warn "ops/ absent — étape ignorée (checkout antérieur à #401 ?)"
        echo
        return 0
    fi

    # --- Crontab ---
    # `__ARBORE_ROOT__` rend le fichier indépendant de l'emplacement du
    # checkout, condition pour qu'un second environnement puisse l'utiliser.
    if [ -f "$SCRIPT_DIR/ops/crontab" ]; then
        local rendered previous
        rendered="$(mktemp)"
        sed "s|__ARBORE_ROOT__|$SCRIPT_DIR|g" "$SCRIPT_DIR/ops/crontab" > "$rendered"

        previous="$(crontab -l 2>/dev/null || true)"
        if [ "$previous" = "$(cat "$rendered")" ]; then
            ok "Crontab déjà conforme"
        else
            # Sauvegarde avant écrasement : une entrée posée à la main serait
            # perdue autrement, et on veut pouvoir la retrouver.
            if [ -n "$previous" ]; then
                printf '%s\n' "$previous" > "$SCRIPT_DIR/logs/crontab.bak.$(date -u +%Y%m%dT%H%M%SZ)"
            fi
            crontab "$rendered"
            ok "Crontab installé ($(grep -cE '^[^#]' "$rendered" | tr -d ' ') entrées)"
        fi
        rm -f "$rendered"
    fi

    # --- Scripts privilégiés + unités systemd ---
    # Non bloquant : sans sudo, le déploiement applicatif doit continuer.
    if ! sudo -n true 2>/dev/null; then
        warn "sudo indisponible — systemd et /usr/local/sbin non appliqués"
        echo
        return 0
    fi

    local changed=0
    for src in "$SCRIPT_DIR"/ops/sbin/*.sh; do
        [ -e "$src" ] || continue
        local dst="/usr/local/sbin/$(basename "$src")"
        if ! sudo cmp -s "$src" "$dst" 2>/dev/null; then
            sudo install -m 0755 "$src" "$dst"
            changed=1
        fi
    done

    local units_changed=0
    for src in "$SCRIPT_DIR"/ops/systemd/*; do
        [ -e "$src" ] || continue
        local dst="/etc/systemd/system/$(basename "$src")"
        if ! sudo cmp -s "$src" "$dst" 2>/dev/null; then
            sudo install -m 0644 "$src" "$dst"
            units_changed=1
        fi
    done

    if [ "$units_changed" -eq 1 ]; then
        sudo systemctl daemon-reload
        for src in "$SCRIPT_DIR"/ops/systemd/*.service "$SCRIPT_DIR"/ops/systemd/*.timer; do
            [ -e "$src" ] || continue
            sudo systemctl enable "$(basename "$src")" > /dev/null 2>&1 || true
        done
        ok "Unités systemd mises à jour et activées"
    elif [ "$changed" -eq 1 ]; then
        ok "Scripts /usr/local/sbin mis à jour"
    else
        ok "systemd et scripts déjà conformes"
    fi
    echo
}

# ───── [3/7] Pre-deploy DB snapshot ───────────────────────────────
#
# Mongo Atlas M0 (tier gratuit) n'a pas de backup automatique. Ce
# mongodump local sert de filet de sécurité juste avant tout redémarrage
# du backend. La récupération est manuelle via mongorestore.
#
# Le dump et le tar tournent dans un tmpdir puis le résultat compressé
# est déplacé dans backups/daily/. Si l'une des étapes échoue, on abort
# pour ne pas déployer une nouvelle version sans filet.
do_db_snapshot() {
    step 3 "Pre-deploy DB snapshot..."

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

# ───── [4/7] Docker compose build ─────────────────────────────────
do_docker_build() {
    local git_sha
    git_sha="$(git rev-parse HEAD)"
    step 4 "Docker compose build (commit ${git_sha:0:7})..."
    # GIT_COMMIT est injecté dans le binaire backend puis renvoyé par GET /health :
    # c'est ce qui rend une dérive prod ↔ main détectable d'un simple curl (#341).
    # L'assignation vient après DOCKER_PRIVILEGE, cf. le commentaire à sa définition.
    if ! "${DOCKER_PRIVILEGE[@]}" GIT_COMMIT="$git_sha" docker compose build backend ai-generator web; then
        fail "docker compose build a échoué"
        exit 1
    fi
    ok "Build réussi"
    echo
}

# ───── [5/7] Docker compose up ────────────────────────────────────
do_docker_up() {
    step 5 "Redémarrage des containers..."
    if ! "${DOCKER_COMPOSE[@]}" up -d backend ai-generator web; then
        fail "docker compose up a échoué"
        exit 1
    fi
    ok "Containers redémarrés"
    echo
}

# ───── [6/7] Logs de démarrage ────────────────────────────────────
do_show_logs() {
    step 6 "Logs de démarrage (10 dernières lignes)..."
    sleep 5
    "${DOCKER_COMPOSE[@]}" logs --tail 10 backend 2>&1 || true
    echo
}

# ───── [7/7] Health check ─────────────────────────────────────────
#
# Le backend expose /health en HTTP plain sur :8080 à ce stade
# (cf. issue #121 pour la migration HTTPS). Le check est bloquant :
# un health != 200 fait sortir en erreur pour signaler clairement
# qu'il faut intervenir.
# La communauté est désactivée avant publication. Un 404 confirme que
# l'ancienne surface publique n'est plus enregistrée par le backend.
check_community_disabled() {
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
        http://localhost:8080/api/v1/community/feed || true)"

    if [ "$code" = "404" ]; then
        ok "Community disabled (404 attendu)"
    else
        fail "Community route: HTTP ${code:-000} (404 attendu tant que la modération n'est pas disponible)"
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
    step 7 "Health check..."
    local attempts=0
    local max_attempts=10
    local http_code=""

    while [ "$attempts" -lt "$max_attempts" ]; do
        http_code="$(curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/health || echo "000")"
        if [ "$http_code" = "200" ]; then
            ok "Backend health 200 OK"
            check_community_disabled
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
    do_apply_ops
    do_db_snapshot
    do_docker_build
    do_docker_up
    do_show_logs
    do_health_check
    footer
}

main "$@"
