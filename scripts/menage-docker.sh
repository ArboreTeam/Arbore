#!/usr/bin/env bash
#
# menage-docker.sh — rétention du cache de compilation et des images Docker.
#
# POURQUOI CE SCRIPT EXISTE
#
# L'ancienne machine de production est morte de ça. Mesure du 2026-10-20, sur
# un disque de 49 Go :
#
#   Images          184   10,02 Go   dont 9,835 Go récupérables (98 %)
#   Build Cache     164   23,10 Go   dont 23,10 Go récupérables
#
# 34 Go récupérables sur 49, alors que les vraies données faisaient 14 Go. La
# migration vers un disque de 100 Go (#652) ne réglait donc rien : un disque
# plus grand sans rétention, c'est un robinet de plus sur une baignoire sans
# bonde.
#
# Et la démonstration n'a pas tardé. Mesure du 2026-11-05 sur la machine
# NEUVE, deux semaines après sa mise en service :
#
#   Build Cache     136   27,80 Go   dont 24,68 Go récupérables
#
# Déjà plus de cache que l'ancienne n'en avait jamais accumulé.
#
# D'OÙ VIENT CE CACHE
#
# De `deploy.sh`, qui construit localement quand les images `sha-` ne sont pas
# encore publiées sur ghcr au moment du déploiement. Chaque repli laisse des
# couches derrière lui, et rien ne les reprend jamais : le déploiement suivant
# tire l'image depuis ghcr.
#
# CE QUE CE SCRIPT NE FAIT PAS
#
# Il ne touche à aucune image utilisée par un conteneur — `docker image prune`
# refuse de les retirer, et c'est une garantie du moteur, pas une précaution
# de ce script. Il ne touche pas non plus aux volumes : il n'y en a aucun sur
# cette machine (les données sont des montages d'hôte), et en supprimer un
# serait de la perte de données, pas du ménage.
#
# Un retrait d'image est de surcroît réversible : l'image vit sur ghcr, et
# `deploy.sh` la retire. Ce qui est supprimé ici se reconstruit ou se retélécharge.

set -euo pipefail

# Fenêtres de rétention, en heures.
#
# Le cache de compilation ne sert qu'au chemin de REPLI de `deploy.sh`. Passé
# quelques jours, les images `sha-` correspondantes sont publiées depuis
# longtemps, donc le cache ne sera plus jamais relu. 72 h laisse de la marge
# pour une journée de déploiements rapprochés sans rien reconstruire.
RETENTION_CACHE_HEURES="${RETENTION_CACHE_HEURES:-72}"

# Les images, plus longtemps : elles permettent un retour arrière immédiat sans
# retélécharger. 14 jours couvre largement la fenêtre pendant laquelle on
# voudrait revenir sur un déploiement précédent.
RETENTION_IMAGES_HEURES="${RETENTION_IMAGES_HEURES:-336}"

journal() { printf '[menage-docker] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

if ! command -v docker > /dev/null 2>&1; then
    journal "docker introuvable — rien à faire"
    exit 0
fi

# Préfixe de privilège détecté, et non codé en dur : sur le VPS l'utilisateur de
# déploiement n'est pas dans le groupe `docker`, et le cron tourne sous cet
# utilisateur. Même motif que `deploy.sh` et `reconcile-guests.sh`.
DOCKER_PRIVILEGE=()
if ! docker info > /dev/null 2>&1; then
    if sudo -n docker info > /dev/null 2>&1; then
        DOCKER_PRIVILEGE=( sudo )
    else
        journal "socket docker inaccessible, y compris via sudo — abandon" >&2
        exit 5
    fi
fi
dkr() { "${DOCKER_PRIVILEGE[@]}" docker "$@"; }

# PAS DE GARDE-FOU « UN DÉPLOIEMENT TOURNE », ET C'EST VOLONTAIRE.
#
# La première version refusait de s'exécuter si un déploiement était en cours,
# au motif qu'un `builder prune` concurrent d'un build retirerait des couches
# que ce build utilise. Deux raisons de l'avoir retirée.
#
# 1. Le danger n'existe pas. Les deux retraits portent un filtre `until=`, donc
#    ils ne visent QUE des objets plus vieux que la fenêtre. Le cache qu'un
#    build est en train de produire a zéro heure d'âge : il n'est jamais
#    éligible. Le garde-fou défendait contre un risque que le filtre exclut
#    déjà.
#
# 2. Il échouait dans le mauvais sens. Il était écrit `pgrep -f 'deploy\.sh'`,
#    qui matche TOUTE ligne de commande contenant cette chaîne — un `tail` sur
#    le journal de déploiement, un `grep`, une session SSH qui mentionne le
#    fichier. Mesuré à l'essai : il s'est déclenché sans aucun déploiement en
#    cours, parce qu'il matchait le shell de test lui-même.
#
#    Un ménage qui saute en silence, c'est le disque qui se remplit sans que
#    rien ne le signale — exactement la panne que ce script existe pour
#    empêcher, avec une cause de plus et plus difficile à voir.
#
# Mieux vaut pas de garde-fou qu'un garde-fou qui désarme la tâche au hasard
# des processus présents. Si le besoin réapparaît un jour, la réponse est un
# verrou `flock` partagé que `deploy.sh` prend aussi — explicite des deux
# côtés — et non une devinette sur des noms de processus.

avant="$(dkr system df --format '{{.Type}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null || true)"
journal "avant :"
printf '%s\n' "$avant" | sed 's/^/    /'

journal "cache de compilation — retrait de ce qui dépasse ${RETENTION_CACHE_HEURES} h"
dkr builder prune --force --filter "until=${RETENTION_CACHE_HEURES}h" 2>&1 | tail -2 | sed 's/^/    /'

journal "images inutilisées — retrait de ce qui dépasse ${RETENTION_IMAGES_HEURES} h"
# `-a` vise aussi les images étiquetées, pas seulement les « dangling » : ce sont
# les anciennes `sha-` qui pèsent, et elles sont toutes étiquetées. Les images
# d'un conteneur en cours sont épargnées par le moteur.
dkr image prune --all --force --filter "until=${RETENTION_IMAGES_HEURES}h" 2>&1 | tail -2 | sed 's/^/    /'

journal "après :"
dkr system df --format '{{.Type}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null | sed 's/^/    /'

# Le disque en clair dans le journal : c'est la seule ligne qu'on relira six
# mois plus tard pour savoir si la rétention suffit encore.
journal "disque : $(df -h / | awk 'NR==2 {print $3" utilises sur "$2", "$4" libres ("$5")"}')"
