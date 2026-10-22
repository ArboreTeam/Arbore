#!/usr/bin/env python3
"""Passe les coupes validees de l'atelier au format leger, pret pour l'USDZ.

Lit etat.json, retient les plantes validees qui portent une coupe choisie, et
produit pour chacune un GLB bas-polygone a atlas propre dans sortie_light/.
L'etape USDZ se fait ailleurs : elle demande usdcat et usdzip.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

RACINE = Path(__file__).parent
ETAT = RACINE / "etat.json"
SORTIE = RACINE / "sortie_light"
REATLAS = RACINE / "reatlas.py"
PYTHON = "/home/debian/.venv-reatlas/bin/python"


def a_traiter() -> list[tuple[str, Path]]:
    etat = json.loads(ETAT.read_text())
    lot = []
    for nom, p in sorted(etat["plantes"].items()):
        if p.get("verdict") != "validee" or not p.get("coupe"):
            continue
        src = RACINE / "plantes" / nom / p["coupe"]
        if src.exists():
            lot.append((nom, src))
    return lot


def main() -> None:
    cible = int(sys.argv[1]) if len(sys.argv) > 1 else 40000
    taille = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
    SORTIE.mkdir(exist_ok=True)
    lot = a_traiter()
    print(f"{len(lot)} coupes validees a traiter -> {SORTIE}", flush=True)

    t0 = time.time()
    faits, echecs = [], []
    for i, (nom, src) in enumerate(lot, 1):
        out = SORTIE / f"{nom}.glb"
        if out.exists():
            print(f"[{i:2}/{len(lot)}] {nom:42} deja fait", flush=True)
            faits.append(nom)
            continue
        r = subprocess.run([PYTHON, str(REATLAS), str(src), str(out), str(cible), str(taille)],
                           capture_output=True, text=True, timeout=900)
        if r.returncode == 0 and out.exists():
            print(f"[{i:2}/{len(lot)}] {nom:42} "
                  f"{src.stat().st_size/1e6:6.1f} -> {out.stat().st_size/1e6:5.2f} Mo", flush=True)
            faits.append(nom)
        else:
            print(f"[{i:2}/{len(lot)}] {nom:42} ECHEC {(r.stderr or r.stdout).strip()[-200:]}",
                  flush=True)
            echecs.append(nom)

    poids = sum(os.path.getsize(SORTIE / f"{n}.glb") for n in faits) / 1e6
    print(f"\n{len(faits)} produits, {len(echecs)} echecs, {poids:.0f} Mo au total, "
          f"{time.time()-t0:.0f} s", flush=True)
    if echecs:
        print("echecs :", echecs, flush=True)


if __name__ == "__main__":
    main()
