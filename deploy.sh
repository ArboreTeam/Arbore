#!/usr/bin/env bash
#
# deploy.sh — Déploiement automatisé d'Arbore (backend + ai-generator + web) sur le VPS.
#
# Enchaîne :
#   1. git pull --ff-only
#   2. mongodump pre-deploy → backups/daily/arbore-predeploy-<ISO>.tar.gz
#   3. rotation des snapshots > 14 jours
#   4. tirage des images ghcr (repli : build local)
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
# Un projet compose PAR ENVIRONNEMENT (#434). Sans nom de projet, compose le
# déduit du nom du répertoire — identique pour les deux piles, qui se
# recycleraient mutuellement : démarrer dev arrêterait la production, sans
# qu'aucune commande n'échoue.
ARBORE_ENV="${ARBORE_ENV:-prod}"
COMPOSE_PROJECT="arbore-$ARBORE_ENV"

# Un fichier d'environnement PAR déploiement. Les deux piles partagent le
# répertoire, donc le `.env` unique d'avant : un déploiement dev y aurait écrit
# ses valeurs, et la production les aurait reprises à son redémarrage suivant.
#
# La production garde `.env` tel quel — pas de migration, pas de risque sur
# l'existant. Les autres environnements prennent `.env.<nom>`.
if [ "$ARBORE_ENV" = "prod" ]; then
    ENV_FILE="$SCRIPT_DIR/.env"
else
    ENV_FILE="$SCRIPT_DIR/.env.$ARBORE_ENV"
fi

# ARBORE_ENV est passée en ARGUMENT de sudo, pas exportée : sudo efface
# l'environnement. Un simple `export` n'atteindrait jamais compose, et
# `container_name` résoudrait toujours vers `arbore-prod-…` — déployer dev
# recyclerait donc les conteneurs de PRODUCTION, sans qu'aucune commande
# n'échoue. Même raison que pour GIT_COMMIT et ARBORE_IMAGE_TAG.
DOCKER_COMPOSE=( "${DOCKER_PRIVILEGE[@]}" ARBORE_ENV="$ARBORE_ENV" docker compose -p "$COMPOSE_PROJECT" --env-file "$ENV_FILE" )

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
    # Le fichier d'environnement peut légitimement ne pas exister encore :
    # c'est `apply_secrets`, à l'étape 2, qui le produit en déchiffrant
    # `ops/secrets/<env>.enc.env`. Exiger sa présence ici rendait impossible
    # l'AMORÇAGE d'un environnement — le script refusait de démarrer sur la
    # chose qu'il allait créer, ce qui contredisait le critère de #401 §1
    # (« git clone, fournir les secrets, déployer »).
    #
    # On accepte donc l'une OU l'autre des deux sources. Si aucune n'est là,
    # rien ne pourra produire la configuration et l'échec est justifié.
    local enc_source="$SCRIPT_DIR/ops/secrets/$ARBORE_ENV.enc.env"
    local age_key="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/arbore-$ARBORE_ENV.txt}"
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f "$enc_source" ] && [ -f "$age_key" ]; then
            warn "$(basename "$ENV_FILE") absent — sera produit par apply_secrets depuis $(basename "$enc_source")"
        else
            fail "$(basename "$ENV_FILE") manquant, et rien pour le produire"
            [ -f "$enc_source" ] || fail "  → $(basename "$enc_source") introuvable"
            [ -f "$age_key" ] || fail "  → clé age introuvable ($age_key)"
            missing=1
        fi
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

    # Garde-fou de branche (#384). `git pull --ff-only` suit la branche COURANTE
    # du checkout : si quelqu'un en laisse une autre en place sur la machine, le
    # script la déploierait sans rien signaler. La dérive ne serait visible qu'en
    # aval, par le commit exposé dans /health.
    #
    # Paramétrable plutôt que codé en dur : #401 vise plusieurs environnements,
    # et une machine de staging déploierait légitimement `dev`. La production ne
    # définit pas la variable et refuse donc tout sauf `main`.
    local expected_branch="${ARBORE_DEPLOY_BRANCH:-main}"
    local current_branch
    current_branch="$(git rev-parse --abbrev-ref HEAD)"
    if [ "$current_branch" != "$expected_branch" ]; then
        fail "Checkout sur '$current_branch', attendu '$expected_branch' — déploiement refusé"
        fail "Pour déployer une autre branche : ARBORE_DEPLOY_BRANCH=<branche> ./deploy.sh"
        exit 1
    fi

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

# apply_secrets — déchiffre les secrets versionnés vers leurs emplacements.
#
# SANS EFFET si la clé privée age est absente : le `.env` en place est alors
# conservé tel quel, et le déploiement continue. C'est la propriété la plus
# importante de cette fonction — une machine sans clé doit se déployer comme
# avant, pas échouer ni se retrouver sans configuration.
#
# `ARBORE_ENV` choisit le jeu de secrets (`prod` par défaut), ce qui prépare
# les environnements multiples visés par #401.
apply_secrets() {
    local env_name="${ARBORE_ENV:-prod}"
    local enc_dir="$SCRIPT_DIR/ops/secrets"
    local key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/arbore-$env_name.txt}"

    [ -d "$enc_dir" ] || return 0

    if ! command -v sops > /dev/null 2>&1; then
        warn "sops absent — secrets non déchiffrés, configuration en place conservée"
        return 0
    fi
    if [ ! -f "$key_file" ]; then
        warn "Clé age introuvable ($key_file) — secrets non déchiffrés, configuration en place conservée"
        return 0
    fi

    # Les fichiers en clair ne doivent jamais être lisibles par autrui, même
    # une fraction de seconde.
    umask 077

    # Dérivé, jamais en dur : `arbore-data/` est le frère du checkout. Un chemin
    # contenant « fedora » enfermait le script sur une machine dont l'utilisateur
    # porte ce nom — or le dépôt doit produire un déploiement sur N machines
    # (#401), et celles d'après février n'auront pas cet utilisateur.
    local data_dir="${ARBORE_DATA_DIR:-$(dirname "$SCRIPT_DIR")/arbore-data}"
    local secrets_dir="$data_dir/secrets"
    # source_chiffrée:destination
    local mappings=(
        "$enc_dir/$env_name.enc.env:$ENV_FILE"
        "$enc_dir/$env_name.enc.json:$secrets_dir/firebase-adminsdk.json"
        "$enc_dir/$env_name.enc.p8:$secrets_dir/apple-siwa.p8"
        "$enc_dir/$env_name.enc.key:$secrets_dir/master-encryption.key"
    )

    local applied=0 unchanged=0 entry src dst tmp
    for entry in "${mappings[@]}"; do
        src="${entry%%:*}"
        dst="${entry#*:}"
        [ -f "$src" ] || continue

        tmp="$(mktemp)"
        # Déchiffrement vérifié AVANT toute écriture sur la destination : un
        # échec ne doit jamais laisser un fichier tronqué ou vide en place.
        if ! SOPS_AGE_KEY_FILE="$key_file" sops --decrypt "$src" > "$tmp" 2> /dev/null; then
            rm -f "$tmp"
            fail "Déchiffrement de $(basename "$src") échoué — destination inchangée"
            return 1
        fi
        if [ ! -s "$tmp" ]; then
            rm -f "$tmp"
            fail "$(basename "$src") déchiffré vide — destination inchangée"
            return 1
        fi

        if [ -f "$dst" ] && cmp -s "$tmp" "$dst"; then
            unchanged=$((unchanged + 1))
            rm -f "$tmp"
            continue
        fi

        # Sauvegarde avant remplacement : une valeur posée à la main sur la
        # machine resterait ainsi récupérable.
        if [ -f "$dst" ]; then
            cp -a "$dst" "$SCRIPT_DIR/logs/$(basename "$dst").bak.$(date -u +%Y%m%dT%H%M%SZ)" 2> /dev/null || true
        fi
        install -m 0600 "$tmp" "$dst" 2> /dev/null || sudo install -m 0600 "$tmp" "$dst"
        rm -f "$tmp"
        applied=$((applied + 1))
    done

    if [ "$applied" -gt 0 ]; then
        ok "Secrets déchiffrés ($env_name) : $applied appliqué(s), $unchanged inchangé(s)"
    else
        ok "Secrets déjà conformes ($env_name)"
    fi
}

# apply_nginx — installe la configuration du reverse-proxy.
#
# Validée par `nginx -t` AVANT rechargement : une configuration fautive
# interrompt le déploiement sans toucher au service en cours. Sans cette
# vérification, un rechargement sur une syntaxe invalide couperait le site.
#
# Sans effet si nginx n'est pas installé — une machine qui n'en a pas se
# déploie comme avant.
apply_nginx() {
    local src_dir="$SCRIPT_DIR/ops/nginx"
    [ -d "$src_dir" ] || return 0

    if ! command -v nginx > /dev/null 2>&1; then
        warn "nginx absent — configuration non appliquée"
        return 0
    fi
    if ! sudo -n true 2>/dev/null; then
        warn "sudo indisponible — configuration nginx non appliquée"
        return 0
    fi

    local changed=0 src name dst backup_dir
    backup_dir="$SCRIPT_DIR/logs/nginx.bak.$(date -u +%Y%m%dT%H%M%SZ)"

    for src in "$src_dir"/*.conf; do
        [ -e "$src" ] || continue
        name="$(basename "$src")"
        dst="/etc/nginx/conf.d/$name"
        if sudo cmp -s "$src" "$dst" 2>/dev/null; then
            continue
        fi
        # Sauvegarde avant écrasement : un réglage posé à la main reste
        # récupérable.
        if [ -f "$dst" ]; then
            mkdir -p "$backup_dir"
            sudo cp -a "$dst" "$backup_dir/$name" 2>/dev/null || true
        fi
        sudo install -m 0644 "$src" "$dst"
        changed=1
    done

    if [ "$changed" -eq 0 ]; then
        ok "nginx déjà conforme"
        return 0
    fi

    # Validation APRÈS installation mais AVANT rechargement : nginx ne sait
    # tester qu'une arborescence en place. En cas d'échec, on restaure.
    if ! sudo nginx -t > /dev/null 2>&1; then
        fail "Configuration nginx invalide — restauration"
        if [ -d "$backup_dir" ]; then
            for name in "$backup_dir"/*; do
                [ -e "$name" ] && sudo install -m 0644 "$name" "/etc/nginx/conf.d/$(basename "$name")"
            done
        fi
        sudo nginx -t > /dev/null 2>&1 && fail "État précédent restauré" || fail "ATTENTION : nginx reste invalide"
        return 1
    fi

    sudo systemctl reload nginx
    ok "nginx mis à jour et rechargé"
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

    apply_secrets
    apply_nginx

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

    # Rejouer les services `oneshot` quand leur script ou leur unité a changé.
    #
    # Sans ceci, installer un script ne l'exécute jamais : le fichier change sur
    # disque, le comportement pas. Un correctif de pare-feu resterait sans effet
    # jusqu'au prochain redémarrage de la machine — et rien ne le signalerait.
    # C'est le mode d'échec de #341 appliqué à ops/ (#434).
    #
    # Restreint aux `oneshot` : rejouer un service au long cours couperait le
    # service qu'il rend. Ceux-ci sont idempotents par conception, et
    # cf-http-firewall.sh porte sa propre liste de repli, donc il ne dépend pas
    # d'un rafraîchissement préalable des plages.
    if [ "$changed" -eq 1 ] || [ "$units_changed" -eq 1 ]; then
        local unit name replayed=0
        for unit in "$SCRIPT_DIR"/ops/systemd/*.service; do
            [ -e "$unit" ] || continue
            grep -q '^Type=oneshot' "$unit" || continue
            name="$(basename "$unit")"
            if sudo systemctl restart "$name" 2>/dev/null; then
                replayed=$((replayed + 1))
            else
                warn "$name n'a pas pu être rejoué — voir journalctl -u $name"
            fi
        done
        [ "$replayed" -gt 0 ] && ok "Services oneshot rejoués : $replayed"
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
    mongo_uri="$(grep '^MONGODB_URI=' "$ENV_FILE" | sed 's/^MONGODB_URI=//' || true)"
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

# ───── [4/7] Images (tirage ghcr, repli build local) ──────────────
#
# Le VPS buildait les trois images à chaque déploiement : ~10 min de CPU et
# plusieurs Go de couches intermédiaires sur un disque déjà tendu, pour
# reproduire un build que la CI vient de faire sur `main` (#425).
#
# On tire donc l'image publiée pour le commit courant. Le repli sur un build
# local est délibéré : un déploiement ne doit pas dépendre de la disponibilité
# de ghcr, et une image peut manquer (workflow en cours, `fail-fast: false` qui
# a laissé passer un service). Le repli est bruyant, jamais silencieux — c'est
# exactement le mode d'échec de #341, où la prod a dérivé sans que rien ne le
# signale.
IMAGE_TAG="latest"

# Authentification ghcr.
#
# ⚠️ Une GitHub App NE FONCTIONNE PAS ici, et ce n'est pas une erreur de
# configuration. La permission `packages: read` d'une App ne donne pas le droit
# de tirer depuis ghcr, et ghcr n'accepte pas les jetons d'installation d'App.
# C'est une limitation de plateforme reconnue par GitHub :
#   https://github.com/orgs/community/discussions/171423
#
# Éprouvé ici le 2026-09-07 avec l'App `arbore-vps-deploy` (permissions
# `metadata: read`, `packages: read`, package correctement rattaché au dépôt) :
# `docker login` réussit, puis la lecture du manifeste renvoie 403 et l'API REST
# 404. L'authentification passe, l'autorisation non.
#
# Les seuls modes acceptés pour un package PRIVÉ sont le PAT classique et le
# `GITHUB_TOKEN` interne à Actions — indisponible hors runner. D'où le PAT.
#
# Il DOIT appartenir à un compte machine, pas à une personne : une production
# ne doit pas dépendre d'un compte individuel qui part avec son propriétaire.
ghcr_login() {
    local token user
    token="$(grep '^GHCR_TOKEN=' "$ENV_FILE" | sed 's/^GHCR_TOKEN=//' || true)"
    user="$(grep '^GHCR_USER=' "$ENV_FILE" | sed 's/^GHCR_USER=//' || true)"

    if [ -z "$token" ] || [ -z "$user" ]; then
        return 1
    fi

    # --password-stdin : le jeton ne passe ni par argv (visible dans ps) ni par
    # l'environnement.
    if ! printf '%s' "$token" \
        | "${DOCKER_PRIVILEGE[@]}" docker login ghcr.io -u "$user" --password-stdin >/dev/null 2>&1; then
        warn "docker login ghcr refusé — jeton expiré ou révoqué ?"
        return 1
    fi
    return 0
}

do_docker_images() {
    local git_sha
    git_sha="$(git rev-parse HEAD)"
    step 4 "Images pour le commit ${git_sha:0:7}..."

    local wanted="sha-$git_sha"

    # L'authentification est tentée mais n'est PAS une condition du tirage : un
    # package public se tire sans identifiants. Conditionner le pull au login
    # ferait rebâtir en local à chaque déploiement, sans que rien ne le dise.
    if ghcr_login; then
        ok "Authentifié sur ghcr"
    else
        warn "Pas d'authentification ghcr — tirage tenté en anonyme"
    fi

    # ARBORE_IMAGE_TAG est consommée par docker-compose.yml. L'assignation vient
    # après DOCKER_PRIVILEGE, cf. le commentaire à sa définition.
    if "${DOCKER_PRIVILEGE[@]}" ARBORE_ENV="$ARBORE_ENV" ARBORE_IMAGE_TAG="$wanted" \
        docker compose -p "$COMPOSE_PROJECT" --env-file "$ENV_FILE" pull backend ai-generator web; then
        IMAGE_TAG="$wanted"
        ok "Images tirées depuis ghcr ($wanted)"
        echo
        return 0
    fi

    warn "Tirage ghcr échoué pour $wanted — repli sur un build local"

    # Repli. On étiquette avec le même nom que l'image attendue : `up` retrouve
    # alors l'image en local et ne retente pas de la tirer.
    # GIT_COMMIT est injecté dans le binaire backend puis renvoyé par GET /health :
    # c'est ce qui rend une dérive prod ↔ main détectable d'un simple curl (#341).
    if ! "${DOCKER_PRIVILEGE[@]}" ARBORE_ENV="$ARBORE_ENV" GIT_COMMIT="$git_sha" ARBORE_IMAGE_TAG="$wanted" \
        docker compose -p "$COMPOSE_PROJECT" --env-file "$ENV_FILE" build backend ai-generator web; then
        fail "docker compose build a échoué"
        exit 1
    fi
    IMAGE_TAG="$wanted"
    ok "Build local réussi"
    echo
}

# ───── [5/7] Docker compose up ────────────────────────────────────
# Conteneurs de l'ancienne pile, antérieure au nommage par projet (#434).
#
# Renommer le projet compose ORPHELINE l'ancienne pile au lieu de la remplacer :
# compose ne la connaît plus, donc ne l'arrête pas, et ses conteneurs retiennent
# les ports. Le `up` échoue alors sur « port is already allocated », en laissant
# l'ancienne pile debout — le service continue, mais le déploiement ne passe
# jamais.
#
# Idempotent : sans effet dès que la migration a eu lieu une fois.
LEGACY_CONTAINERS=( arbore-backend arbore-web arbore-ai-generator arbore-minio )

drop_legacy_containers() {
    local name found=0
    for name in "${LEGACY_CONTAINERS[@]}"; do
        if "${DOCKER_PRIVILEGE[@]}" docker ps -a --format '{{.Names}}' 2>/dev/null \
            | grep -qx "$name"; then
            "${DOCKER_PRIVILEGE[@]}" docker rm -f "$name" > /dev/null 2>&1 || true
            found=$((found + 1))
        fi
    done
    if [ "$found" -gt 0 ]; then
        warn "Ancienne pile retirée ($found conteneur(s) sans nom de projet) — migration #434"
    fi
}

do_docker_up() {
    step 5 "Redémarrage des containers..."
    drop_legacy_containers
    if ! "${DOCKER_PRIVILEGE[@]}" ARBORE_ENV="$ARBORE_ENV" ARBORE_IMAGE_TAG="$IMAGE_TAG" \
        docker compose -p "$COMPOSE_PROJECT" --env-file "$ENV_FILE" up -d backend ai-generator web; then
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
        warn "Web: HTTP $code sur :3000 (non bloquant — voir 'sudo docker logs --tail 50 arbore-${ARBORE_ENV:-prod}-web')"
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
    fail "Vérifier les logs : sudo docker logs --tail 50 arbore-${ARBORE_ENV:-prod}-backend"
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
    do_docker_images
    do_docker_up
    do_show_logs
    do_health_check
    footer
}

main "$@"
