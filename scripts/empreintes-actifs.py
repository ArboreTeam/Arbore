#!/usr/bin/env python3
"""Calcule l'empreinte des fichiers servis, pour invalider le cache. (#294, #524)

## Le défaut réparé

Le cache iOS des modèles est indexé par **nom de fichier**, dans
`Documents/Models/`, que la mise à jour d'une app ne vide pas. Un fichier
réécrit sous le même nom n'atteint donc aucun appareil l'ayant déjà
téléchargé. C'est #292 : les testeurs ont gardé des modèles gris jusqu'à ce
qu'ils réinstallent.

## Pourquoi une empreinte, et pas un compteur

#524 a mesuré ce que coûte la constante globale compilée dans le binaire,
déjà en place pour les vignettes : la changer invalide **tout** le catalogue
chez tout le monde, et n'atteint personne sans une nouvelle livraison. Sur des
modèles 3D, ce serait 440 Mo en light.

L'empreinte du contenu change quand les octets changent, jamais autrement,
personne n'a à penser à l'incrémenter, et elle voyage avec la fiche — que
l'app lit déjà.

## Ce que ce script lit, et ne lit pas

Il lit **les fichiers réellement servis**, pas ce qu'on croit avoir déployé.
C'est le point : une empreinte calculée sur une copie locale mentirait le jour
où le déploiement aurait échoué à mi-chemin.

Il n'ouvre aucune base. Comme les autres scripts de catalogue, il émet des
opérations ; l'écriture reste un geste séparé et relu.

  python3 scripts/empreintes-actifs.py --modeles /chemin/models [--heavy ...]
                                       [--vignettes ...] [--out ops.json]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

# Huit caractères hexadécimaux. Ce n'est pas une signature : la valeur ne
# protège de rien, elle répond à « est-ce le même fichier qu'avant ». Doit
# rester égal à `longueurEmpreinte` dans ArboreBackend/assetversions.go.
LONGUEUR = 8

# Lu par blocs : un modèle heavy atteint 80 Mo, rien n'oblige à le tenir en
# mémoire pour le résumer.
BLOC = 1 << 20


def empreinte(chemin: Path) -> str:
    h = hashlib.sha256()
    with chemin.open("rb") as f:
        while bloc := f.read(BLOC):
            h.update(bloc)
    return h.hexdigest()[:LONGUEUR]


def empreintes_du_repertoire(repertoire: Path | None, motif: str) -> dict[str, str]:
    """Empreinte de chaque fichier d'un répertoire, par nom de fichier."""
    if repertoire is None or not repertoire.is_dir():
        return {}
    return {f.name: empreinte(f) for f in sorted(repertoire.glob(motif)) if f.is_file()}


def operations(light: dict[str, str], heavy: dict[str, str],
               vignettes: dict[str, str], pots: set[str]) -> dict:
    """Opérations à appliquer, séparées par ce qu'elles visent.

    Les plantes sont visées par `modelURL`, seule valeur que l'atelier, le
    disque et le catalogue partagent. Les vignettes sont nommées d'après
    l'identifiant de la fiche, donc visées par `_id`. Les pots ont leur propre
    collection.
    """
    plantes, entrees_pots = [], []
    for nom, h in sorted(light.items()):
        if nom in pots:
            continue
        champs = {"versions.model": h}
        if nom in heavy:
            champs["versions.modelHeavy"] = heavy[nom]
        plantes.append({"modelURL": nom, "set": champs})

    for nom in sorted(pots):
        if nom in light:
            entrees_pots.append({"modelURL": nom, "set": {"version": light[nom]}})

    return {
        "plantes": plantes,
        "pots": entrees_pots,
        # Clé = identifiant de fiche, le nom de fichier étant `<id>.png`.
        "vignettes": [{"id": Path(n).stem, "set": {"versions.thumbnail": h}}
                      for n, h in sorted(vignettes.items())],
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--modeles", required=True, help="répertoire des USDZ light servis")
    ap.add_argument("--heavy", help="répertoire des USDZ heavy servis")
    ap.add_argument("--vignettes", help="répertoire des vignettes servies")
    ap.add_argument("--pots", default="", help="noms de fichiers de pots, séparés par des virgules")
    ap.add_argument("--out")
    args = ap.parse_args()

    light = empreintes_du_repertoire(Path(args.modeles), "*.usdz")
    heavy = empreintes_du_repertoire(Path(args.heavy) if args.heavy else None, "*.usdz")
    vign = empreintes_du_repertoire(Path(args.vignettes) if args.vignettes else None, "*.png")
    pots = {n.strip() for n in args.pots.split(",") if n.strip()}

    ops = operations(light, heavy, vign, pots)

    print(f"  modèles light  : {len(light)}", file=sys.stderr)
    print(f"  modèles heavy  : {len(heavy)}", file=sys.stderr)
    print(f"  vignettes      : {len(vign)}", file=sys.stderr)
    print(f"  pots           : {len(ops['pots'])}", file=sys.stderr)
    orphelins = sorted(set(heavy) - set(light))
    if orphelins:
        # Un heavy sans light ne sera jamais demandé : le client part du light.
        print(f"  heavy sans light : {len(orphelins)} {orphelins[:3]}", file=sys.stderr)
    doublons = sorted(n for n, h in light.items() if list(light.values()).count(h) > 1)
    if doublons:
        print(f"  ATTENTION empreintes en double : {doublons[:4]}", file=sys.stderr)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(ops, f, ensure_ascii=False, indent=1)
        print(f"  écrit : {args.out}", file=sys.stderr)
    else:
        json.dump(ops, sys.stdout, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
