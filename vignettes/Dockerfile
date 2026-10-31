# Rendu des vignettes du catalogue, hors de tout environnement Apple. (#694, #695)
#
# Pourquoi une image et non une installation hôte : la version de Blender est
# épinglée ICI, donc identique sur dev, sur prod et dans le temps. Installée par
# `ops/`, elle serait celle du dépôt de la distribution — la reproductibilité
# serait celle de l'OS, pas la nôtre. `ops/` reste la source de vérité de ce qui
# vit HORS des conteneurs ; ce qui vit dedans se déclare dans l'image.
#
# Pourquoi Blender plutôt qu'un moteur plus léger : 61 des 123 modèles servis
# n'existent qu'en USDZ. Tout moteur ne lisant que le glTF exigerait une
# conversion dont on ne dispose pas sous Linux. Blender importe l'USD
# nativement. Mesure du 2026-10-31, consignée dans #694.
FROM debian:12-slim

# 4.2 LTS, et non `latest` : une vignette doit se re-rendre à l'identique dans
# six mois. Le support long terme porte jusqu'en 2026, et son importateur USD
# gère `UsdPreviewSurface`, ce dont nos fichiers sont faits.
ARG BLENDER_VERSION=4.2.5
ARG BLENDER_SERIE=4.2

ENV DEBIAN_FRONTEND=noninteractive

# `libgl1` et consorts : Blender les exige au chargement même en `--background`,
# faute de quoi il échoue sur un lien manquant avant d'exécuter le moindre
# script. `xz-utils` sert à l'archive, `ca-certificates` au téléchargement.
#
# `python3` est celui de Debian, pour l'orchestration seule — appels HTTP et
# contrôles. Le rendu, lui, tourne dans le Python embarqué de Blender, le seul
# qui expose `bpy`. Deux interpréteurs, deux rôles, aucun paquet à installer :
# `urllib` de la bibliothèque standard suffit, donc pas de pip ni de requests.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils python3 \
        libgl1 libglx-mesa0 libegl1 libxi6 libxxf86vm1 libxfixes3 libxrender1 \
        libsm6 libice6 libxkbcommon0 libdbus-1-3 libwayland-client0 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://download.blender.org/release/Blender${BLENDER_SERIE}/blender-${BLENDER_VERSION}-linux-x64.tar.xz" \
      -o /tmp/blender.tar.xz \
    && mkdir -p /opt/blender \
    && tar -xJf /tmp/blender.tar.xz -C /opt/blender --strip-components=1 \
    && rm /tmp/blender.tar.xz \
    && ln -s /opt/blender/blender /usr/local/bin/blender \
    # SANS tube : `blender --version | head -1` rend le code de sortie de
    # `head`, donc 0 même quand Blender échoue sur une bibliothèque absente.
    # Le build passait, et l'erreur n'apparaissait qu'à la première exécution.
    && ldd /opt/blender/blender | grep -q 'not found' && exit 1 || true \
    && blender --version

WORKDIR /app
COPY rendre.py publier.py ./

# Aucun point d'entrée qui démarre tout seul : c'est un JOB, invoqué
# explicitement. Le service compose est sous profil pour la même raison —
# `docker compose up -d` ne doit jamais le lancer.
ENTRYPOINT ["python3", "/app/publier.py"]
