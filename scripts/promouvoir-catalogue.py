#!/usr/bin/env python3
"""Prépare la promotion d'un catalogue vers un autre environnement. (#809)

Il ne promeut rien lui-même : il lit la base source, la compare à la cible, et
émet un plan — les opérations d'insertion, et la liste des fichiers à
transférer. L'écriture reste un geste séparé, relu et daté, comme pour les
autres scripts de catalogue.

## L'identifiant est conservé, et c'est tout l'enjeu

Une vignette est nommée d'après l'`_id` de sa fiche, et `imageURLs` le
contient. Insérer en laissant Mongo générer un identifiant neuf rendrait donc
inutilisables les vignettes déjà rendues — 151 plantes à re-rendre, environ
cinq heures d'ouvrier, pour un résultat identique à 82 Mo de PNG qu'on peut
simplement copier.

Ce n'est pas un raccourci : les deux bases emploient **déjà** les mêmes
identifiants pour une même plante. Relevé le 2026-11-05 en portant 51 plantes,
les 51 `_id` de dev existaient tous en prod. Conserver l'`_id` maintient cet
invariant ; le laisser dériver le casserait.

## L'ordre des trois gestes n'est pas négociable

  1. **les modèles USDZ** vers le répertoire de la cible ;
  2. **les vignettes** déjà rendues ;
  3. **les fiches** en base.

Une fiche écrite avant son modèle pointe vers un 404, et l'application ne le
dit pas : elle échoue à charger la plante au moment du placement AR. Une fiche
écrite avant sa vignette affiche un trou dans le catalogue. Le script compte ce
qui manque de chaque côté pour que l'ordre puisse être tenu.

## Ce qu'il refuse de promouvoir

Une fiche dont le `modelURL` existe déjà dans la cible sous un AUTRE `_id`.
Le cas ne s'est pas présenté, mais il signifierait que les deux bases ont
divergé, et l'insérer donnerait deux fiches pour une plante.

  MONGODB_URI=... python3 scripts/promouvoir-catalogue.py \\
      --source arbore_dev --cible arbore [--out plan.json]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def plan(source, cible) -> dict:
    """Compare les deux catalogues et rend le plan de promotion."""
    src = {d["_id"]: d for d in source.find({})}
    dst = {d["_id"]: d for d in cible.find({}, {"modelURL": 1})}
    urls_cible = {d.get("modelURL"): i for i, d in dst.items()}

    a_creer, deja, conflits = [], [], []
    for oid, d in src.items():
        if oid in dst:
            deja.append(oid)
            continue
        autre = urls_cible.get(d.get("modelURL"))
        if autre is not None:
            # Même plante, identifiant différent : les bases ont divergé.
            conflits.append((d.get("modelURL"), str(oid), str(autre)))
            continue
        doc = dict(d)
        doc["_id"] = {"$oid": str(oid)}
        a_creer.append(doc)
    return {"a_creer": a_creer, "deja": deja, "conflits": conflits,
            "source": len(src), "cible": len(dst)}


def fichiers(a_creer: list[dict], vign_src: Path | None, vign_dst: Path | None,
             mod_src: Path | None, mod_dst: Path | None) -> dict:
    """Ce qu'il faut transférer, et ce qui manque déjà côté source."""
    r = {"vignettes": [], "vignettes_absentes": [],
         "modeles": [], "modeles_absents": [], "octets": 0}
    for d in a_creer:
        oid = d["_id"]["$oid"]
        if vign_src and vign_dst:
            s, c = vign_src / f"{oid}.png", vign_dst / f"{oid}.png"
            if not s.exists():
                r["vignettes_absentes"].append(oid)
            elif not c.exists():
                r["vignettes"].append(f"{oid}.png")
                r["octets"] += s.stat().st_size
        url = d.get("modelURL")
        if url and mod_src and mod_dst:
            s, c = mod_src / url, mod_dst / url
            if not s.exists():
                r["modeles_absents"].append(url)
            elif not c.exists():
                r["modeles"].append(url)
                r["octets"] += s.stat().st_size
    return r


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", required=True, help="base de départ, à nommer")
    ap.add_argument("--cible", required=True, help="base d'arrivée, à nommer")
    ap.add_argument("--vignettes-source", type=Path)
    ap.add_argument("--vignettes-cible", type=Path)
    ap.add_argument("--modeles-source", type=Path)
    ap.add_argument("--modeles-cible", type=Path)
    ap.add_argument("--out", help="fichier d'opérations pour appliquer-ops-mongo.py")
    a = ap.parse_args()

    if a.source == a.cible:
        print("source et cible sont la même base", file=sys.stderr)
        return 2
    uri = os.environ.get("MONGODB_URI", "").strip()
    if not uri:
        print("MONGODB_URI absente de l'environnement", file=sys.stderr)
        return 2

    from pymongo import MongoClient

    c = MongoClient(uri)
    p = plan(c[a.source]["plants"], c[a.cible]["plants"])
    f = fichiers(p["a_creer"], a.vignettes_source, a.vignettes_cible,
                 a.modeles_source, a.modeles_cible)

    print(f"  {a.source} : {p['source']} fiches | {a.cible} : {p['cible']}", file=sys.stderr)
    print(f"  fiches à créer        : {len(p['a_creer'])}", file=sys.stderr)
    print(f"  déjà dans la cible    : {len(p['deja'])}", file=sys.stderr)
    print(f"  CONFLITS              : {len(p['conflits'])}", file=sys.stderr)
    for url, a_, b_ in p["conflits"][:10]:
        print(f"      {url} — source {a_}, cible {b_}", file=sys.stderr)
    print(f"  modèles à transférer  : {len(f['modeles'])}", file=sys.stderr)
    print(f"  vignettes à copier    : {len(f['vignettes'])}", file=sys.stderr)
    print(f"  volume total          : {f['octets'] / 1024 / 1024:.0f} Mo", file=sys.stderr)
    if f["modeles_absents"]:
        print(f"  ⚠️  modèles ABSENTS de la source : {len(f['modeles_absents'])} "
              f"{f['modeles_absents'][:3]}", file=sys.stderr)
    if f["vignettes_absentes"]:
        print(f"  ⚠️  vignettes ABSENTES de la source : {len(f['vignettes_absentes'])} "
              f"{f['vignettes_absentes'][:3]}", file=sys.stderr)
    print("  Ordre à tenir : les modèles, puis les vignettes, puis les fiches.",
          file=sys.stderr)

    if a.out:
        Path(a.out).write_text(
            json.dumps({"nouvelles": p["a_creer"]}, ensure_ascii=False, indent=1,
                       default=str),
            encoding="utf-8")
        Path(a.out + ".fichiers").write_text(
            json.dumps({"modeles": f["modeles"], "vignettes": f["vignettes"]},
                       ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"  écrit : {a.out} et {a.out}.fichiers", file=sys.stderr)
    return 1 if p["conflits"] else 0


if __name__ == "__main__":
    sys.exit(main())
