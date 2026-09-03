#!/usr/bin/env bash
# Issue #393 — réconciliation Firebase ↔ Mongo.
#
# Supprime les données Mongo dont l'uid n'existe plus dans Firebase Auth. Le
# nettoyage automatique des comptes anonymes inactifs (activé le 2026-09-02)
# supprime un compte invité après 30 jours ; sans ce job, ses jardins et
# consentements resteraient en base sans propriétaire identifiable.
#
# Cron hebdomadaire, sur le motif de cleanup-test-users.sh :
#
#   0 5 * * 0 /home/fedora/Arbore/ArboreBackend/scripts/reconcile-guests.sh \
#     >> /home/fedora/Arbore/logs/reconcile-guests.log 2>&1
#
# SIMULATION PAR DÉFAUT. Sans argument, le job compte et journalise sans rien
# supprimer. Pour supprimer réellement :
#
#   reconcile-guests.sh --apply
#
# Le job s'exécute DANS le conteneur backend déjà déployé : il y trouve
# MONGODB_URI, le service account Firebase monté en /run/secrets, et surtout la
# même fonction de purge que la suppression de compte RGPD. Rien à builder ni à
# recopier côté hôte.

set -euo pipefail

CONTAINER="${ARBORE_BACKEND_CONTAINER:-arbore-backend}"
APPLY=""

case "${1:-}" in
    --apply)
        APPLY="-apply"
        ;;
    "")
        ;;
    *)
        echo "[reconcile-guests] usage: $0 [--apply]" >&2
        exit 64
        ;;
esac

if ! command -v docker > /dev/null 2>&1; then
    echo "[reconcile-guests] docker introuvable" >&2
    exit 2
fi

# Préfixe de privilège, sur le motif de deploy.sh : sur le VPS l'utilisateur
# `fedora` n'est pas dans le groupe `docker`, et le cron tourne sous cet
# utilisateur. Sans ce préfixe le job échouerait chaque semaine sur un
# « permission denied » du socket. Détecté plutôt que codé en dur, pour rester
# utilisable sur une machine où docker tourne sans privilège.
DOCKER_PRIVILEGE=()
if ! docker info > /dev/null 2>&1; then
    if sudo -n docker info > /dev/null 2>&1; then
        DOCKER_PRIVILEGE=( sudo )
    else
        echo "[reconcile-guests] socket docker inaccessible, y compris via sudo" >&2
        exit 5
    fi
fi

# Le conteneur doit tourner : `docker exec` sur un conteneur arrêté échouerait
# avec un message peu lisible dans un journal de cron.
if [[ "$("${DOCKER_PRIVILEGE[@]}" docker inspect -f '{{.State.Running}}' "$CONTAINER" 2> /dev/null)" != "true" ]]; then
    echo "[reconcile-guests] conteneur '$CONTAINER' absent ou arrêté" >&2
    exit 3
fi

MODE="simulation"
if [[ -n "$APPLY" ]]; then
    MODE="SUPPRESSION RÉELLE"
fi

printf '[reconcile-guests] %s UTC — démarrage (%s)\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$MODE"

# Pas de -t : sortie non interactive, adaptée à la redirection cron.
"${DOCKER_PRIVILEGE[@]}" docker exec -i "$CONTAINER" /app/main -reconcile-guests ${APPLY:+"$APPLY"}

printf '[reconcile-guests] %s UTC — terminé\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
