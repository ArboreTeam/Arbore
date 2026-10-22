#!/usr/bin/env python3
"""Applique les opérations de poser-pots-sur-plantes.py à une base. (#609)

Séparé de la préparation, et volontairement : la préparation se relit sans
risque, l'écriture non. Ce script ne décide de rien — il applique un fichier
d'opérations déjà produit et relu.

## Garde-fous

  - `--base` est obligatoire et doit être nommée explicitement. Aucun défaut,
    pour qu'une étourderie ne vise jamais la production.
  - sans `--appliquer`, le script ne fait que compter ce qu'il ferait.
  - l'URI ne transite jamais par la ligne de commande : elle est lue dans
    `MONGODB_URI`, pour ne pas apparaître dans l'historique ni dans `ps`.
  - une opération dont le filtre ne trouve aucune plante est signalée, pas
    silencieusement ignorée : c'est le symptôme d'un catalogue qui a bougé.
  - une plante déjà basculée est laissée telle quelle, le script est rejouable.

  MONGODB_URI=... python3 scripts/appliquer-pots-mongo.py \\
      --ops ops.json --base arbore_dev [--appliquer]
"""
from __future__ import annotations

import argparse
import json
import os
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ops", required=True)
    ap.add_argument("--base", required=True, help="nom de la base, à nommer explicitement")
    ap.add_argument("--appliquer", action="store_true", help="sans ce drapeau, rien n'est écrit")
    args = ap.parse_args()

    uri = os.environ.get("MONGODB_URI", "").strip()
    if not uri:
        print("MONGODB_URI absente de l'environnement", file=sys.stderr)
        return 2

    from pymongo import MongoClient  # importé tard : absent des machines sans ce besoin

    ops = json.load(open(args.ops, encoding="utf-8"))
    db = MongoClient(uri)[args.base]
    plants, pots = db["plants"], db["pots"]

    introuvables, deja, a_faire = [], 0, []
    for o in ops["plantes"]:
        doc = plants.find_one({"modelURL": o["modelURL"]}, {"_id": 1})
        if doc is None:
            # Déjà basculée ? Le filtre vise l'ancien nom, pas le nouveau.
            if plants.find_one({"modelURL": o["set"]["modelURL"]}, {"_id": 1}):
                deja += 1
            else:
                introuvables.append(o["modelURL"])
            continue
        a_faire.append(o)

    print(f"  plantes à basculer   : {len(a_faire)}", file=sys.stderr)
    print(f"  déjà basculées       : {deja}", file=sys.stderr)
    print(f"  introuvables         : {len(introuvables)} {introuvables[:5]}", file=sys.stderr)
    print(f"  pots à poser         : {len(ops['pots'])}", file=sys.stderr)

    if not args.appliquer:
        print("  — simulation, rien n'a été écrit (ajouter --appliquer)", file=sys.stderr)
        return 0

    for o in a_faire:
        plants.update_one({"modelURL": o["modelURL"]}, {"$set": o["set"]})
    for p in ops["pots"]:
        pots.update_one({"name": p["name"]}, {"$set": p}, upsert=True)

    print(f"  écrit dans {args.base} : {len(a_faire)} plantes, {len(ops['pots'])} pots",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
