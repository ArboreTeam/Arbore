#!/usr/bin/env python3
"""Convertit une coupe d'atelier en USDZ **sans rien réduire**. (#609)

## Pourquoi aucune réduction

La chaîne de reconstruction (`reatlas.py`) ramenait un modèle de 49 Mo à
2,2 Mo, mais au prix du détail : les frondes d'un palmier, finement plissées
dans la source, ressortaient en lames plates. Arbitrage de l'utilisateur, le
2026-10-22 : garder les originaux.

Ce script ne touche donc ni à la géométrie, ni aux textures. Il fait seulement
ce qu'il faut pour qu'ARKit accepte le fichier :

  - déballage du GLB, pour que `usdcat` lise les textures comme des fichiers ;
  - **reliure directe des textures** (#292) : SceneKit ne suit pas
    `inputs:file.connect`, et le modèle ressortirait gris en AR ;
  - `subdivisionScheme = "none"`, sinon l'ARView subdivise au chargement ;
  - `usdzip --arkitAsset`.

## Ce qui n'est PAS fait, et pourquoi

Pas de `doubleSided`. Il ne servait qu'à rattraper la fusion des deux peaux
provoquée par la décimation ; sans elle, les deux peaux subsistent et le
matériau simple face de la source est correct — c'est ainsi que la source se
rend bien.

Pas de conversion de texture. Repasser un PNG en JPEG allégerait, mais c'est
une réduction, et la consigne est de n'en faire aucune.

  python usdz_sans_reduction.py <repertoire_glb> [--out ...] [--workers 2]
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from optimize_models import _inject_subdivision, _rebind_scenekit_textures

SCRIPT_DIR = Path(__file__).parent
GLTF = SCRIPT_DIR / "node_modules" / ".bin" / "gltf-transform"


def _run(cmd: list[str], cwd: Path | None = None) -> None:
    res = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=1800)
    if res.returncode != 0:
        raise RuntimeError(f"{cmd[0]} : {(res.stderr or res.stdout)[-300:]}")


def convertir(glb: Path, out_dir: Path, suffixe: str, force: bool) -> tuple[str, float, float, str]:
    out = out_dir / f"{glb.stem}{suffixe}.usdz"
    src_mb = glb.stat().st_size / 1e6
    if out.exists() and not force:
        return (glb.stem, src_mb, out.stat().st_size / 1e6, "skip")
    try:
        with tempfile.TemporaryDirectory() as td:
            w = Path(td)
            # `copy` déballe sans retoucher : les textures sortent telles quelles.
            _run([str(GLTF), "copy", str(glb), str(w / "m.gltf")])
            _run(["usdcat", "m.gltf", "-o", "m.usda"], cwd=w)
            relie = _rebind_scenekit_textures(w / "m.usda")
            if relie == 0:
                # Aucune texture reliée : le modèle sortirait gris en AR (#292).
                return (glb.stem, src_mb, 0.0, "ECHEC: aucune texture reliee")
            _inject_subdivision(w / "m.usda")
            _run(["usdzip", "--arkitAsset", "m.usda", "out.usdz"], cwd=w)
            out_dir.mkdir(parents=True, exist_ok=True)
            shutil.move(str(w / "out.usdz"), str(out))
        return (glb.stem, src_mb, out.stat().st_size / 1e6, "ok")
    except Exception as e:  # noqa: BLE001
        return (glb.stem, src_mb, 0.0, f"ECHEC: {e}")


def main() -> None:
    p = argparse.ArgumentParser(description="Coupes d'atelier -> USDZ, sans reduction")
    p.add_argument("source", help="repertoire des GLB de coupe")
    p.add_argument("--out", default="trellis_brut")
    p.add_argument("--suffixe", default="_potless")
    # Deux par defaut : chaque conversion tient plusieurs centaines de Mo en
    # fichiers temporaires, et en lancer quatre remplit le disque.
    p.add_argument("--workers", type=int, default=2)
    p.add_argument("--force", action="store_true")
    args = p.parse_args()

    if not GLTF.exists():
        sys.exit("gltf-transform absent — lancer npm install dans Plant3DGenerator/")
    glbs = sorted(Path(args.source).glob("*.glb"))
    if not glbs:
        sys.exit(f"aucun GLB dans {args.source}")
    out_dir = SCRIPT_DIR / args.out if not Path(args.out).is_absolute() else Path(args.out)

    print(f"{len(glbs)} coupes -> {out_dir} (aucune reduction)", flush=True)
    res = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for nom, src, dst, etat in ex.map(
                lambda g: convertir(g, out_dir, args.suffixe, args.force), glbs):
            res.append((nom, src, dst, etat))
            if etat == "ok":
                print(f"  {nom:46} {src:6.1f} -> {dst:6.1f} Mo", flush=True)
            elif etat == "skip":
                print(f"  {nom:46} deja fait ({dst:.1f} Mo)", flush=True)
            else:
                print(f"  {nom:46} {etat}", flush=True)

    ok = [r for r in res if r[3] == "ok"]
    if ok:
        total = sum(r[2] for r in ok)
        print(f"\n{len(ok)} convertis, {total/1000:.2f} Go, moyenne {total/len(ok):.1f} Mo", flush=True)
    echecs = [r[0] for r in res if r[3].startswith("ECHEC")]
    if echecs:
        print(f"{len(echecs)} echecs : {echecs}", flush=True)
    sys.exit(1 if echecs else 0)


if __name__ == "__main__":
    main()
