#!/usr/bin/env python3
"""Applique à une base les opérations produites par les scripts de catalogue.

Séparé de la préparation, et volontairement : la préparation se relit sans
risque, l'écriture non. Ce script ne décide de rien — il applique un fichier
d'opérations déjà produit et relu.

## Les trois sections, et comment chacune vise sa cible

| section | vise | par |
|---|---|---|
| `plantes` | collection `plants` | `modelURL` — seule valeur que l'atelier, le disque et le catalogue partagent |
| `vignettes` | collection `plants` | `_id` — une vignette est nommée d'après la fiche |
| `pots` | collection `pots` | `name` pour une entrée complète, `modelURL` pour une mise à jour |

Une entrée qui porte un champ `set` **met à jour** ; une entrée sans `set` est
un document complet, **inséré ou remplacé**. C'est ce qui permet au même script
de poser la bibliothèque de pots et, plus tard, d'y écrire une empreinte.

## Garde-fous

  - `--base` est obligatoire et doit être nommée explicitement. Aucun défaut,
    pour qu'une étourderie ne vise jamais la production.
  - sans `--appliquer`, le script ne fait que compter ce qu'il ferait.
  - l'URI ne transite jamais par la ligne de commande : elle est lue dans
    `MONGODB_URI`, pour ne pas apparaître dans l'historique ni dans `ps`.
  - une opération dont le filtre ne trouve rien est signalée, pas silencieusement
    ignorée : c'est le symptôme d'un catalogue qui a bougé.
  - le script est **rejouable**. Pour les plantes, le filtre vise l'ancien
    `modelURL` ; une plante déjà basculée ne s'y reconnaît plus, alors on la
    retrouve par son nouveau nom et on lui réapplique la mise à jour. Sans ça,
    une passe ultérieure qui ajoute un champ n'atteindrait jamais les plantes
    de la première passe.

  MONGODB_URI=... python3 scripts/appliquer-ops-mongo.py \\
      --ops ops.json --base arbore_dev [--appliquer]
"""
from __future__ import annotations

import argparse
import json
import os
import sys


def cibler_plantes(plants, ops: list[dict]) -> tuple[list[tuple[dict, dict]], list[str], int]:
    """Associe chaque opération au filtre qui la trouve réellement."""
    a_faire, introuvables, rejouees = [], [], 0
    for o in ops:
        if plants.find_one({"modelURL": o["modelURL"]}, {"_id": 1}):
            a_faire.append(({"modelURL": o["modelURL"]}, o["set"]))
            continue
        # Déjà basculée : le filtre vise l'ancien nom, elle porte le nouveau.
        nouveau = o["set"].get("modelURL")
        if nouveau and plants.find_one({"modelURL": nouveau}, {"_id": 1}):
            a_faire.append(({"modelURL": nouveau}, o["set"]))
            rejouees += 1
            continue
        introuvables.append(o["modelURL"])
    return a_faire, introuvables, rejouees


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
    from bson import ObjectId

    ops = json.load(open(args.ops, encoding="utf-8"))
    db = MongoClient(uri)[args.base]
    plants, pots = db["plants"], db["pots"]

    a_faire, introuvables, rejouees = cibler_plantes(plants, ops.get("plantes") or [])

    vignettes, sans_fiche = [], []
    for v in ops.get("vignettes") or []:
        try:
            oid = ObjectId(v["id"])
        except Exception:  # noqa: BLE001
            sans_fiche.append(v["id"])
            continue
        if plants.find_one({"_id": oid}, {"_id": 1}):
            vignettes.append(({"_id": oid}, v["set"]))
        else:
            # Une vignette servie dont plus aucune fiche ne porte l'identifiant.
            sans_fiche.append(v["id"])

    entrees_pots = ops.get("pots") or []

    print(f"  plantes à écrire       : {len(a_faire)}", file=sys.stderr)
    print(f"  dont déjà basculées    : {rejouees}", file=sys.stderr)
    print(f"  plantes introuvables   : {len(introuvables)} {introuvables[:5]}", file=sys.stderr)
    print(f"  vignettes à écrire     : {len(vignettes)}", file=sys.stderr)
    print(f"  vignettes sans fiche   : {len(sans_fiche)} {sans_fiche[:5]}", file=sys.stderr)
    print(f"  pots                   : {len(entrees_pots)}", file=sys.stderr)

    if not args.appliquer:
        print("  — simulation, rien n'a été écrit (ajouter --appliquer)", file=sys.stderr)
        return 0

    for filtre, maj in a_faire + vignettes:
        plants.update_one(filtre, {"$set": maj})
    for p in entrees_pots:
        if "set" in p:
            pots.update_one({"modelURL": p["modelURL"]}, {"$set": p["set"]})
        else:
            pots.update_one({"name": p["name"]}, {"$set": p}, upsert=True)

    print(f"  écrit dans {args.base} : {len(a_faire)} plantes, {len(vignettes)} vignettes, "
          f"{len(entrees_pots)} pots", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
