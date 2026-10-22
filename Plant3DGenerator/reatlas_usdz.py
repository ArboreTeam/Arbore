#!/usr/bin/env python3
"""Convertit les GLB allegers de reatlas_lot.py en USDZ prets pour ARKit.

Separe de reatlas_lot.py parce que cette etape demande usdcat et usdzip, que la
machine d'atelier n'a pas. Reutilise la reliure de textures et l'injection de
subdivision de optimize_models.py, pour ne pas en tenir deux copies.

  python reatlas_usdz.py <repertoire_glb> [--out opti_trellis] [--workers 4]
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
    res = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=600)
    if res.returncode != 0:
        raise RuntimeError(f"{cmd[0]} : {(res.stderr or res.stdout)[-300:]}")


def convertir(glb: Path, out_dir: Path, taille: int, force: bool) -> tuple[str, float, float, str]:
    out = out_dir / f"{glb.stem}.usdz"
    src_mb = glb.stat().st_size / 1e6
    if out.exists() and not force:
        return (glb.stem, src_mb, out.stat().st_size / 1e6, "skip")
    try:
        with tempfile.TemporaryDirectory() as td:
            w = Path(td)
            # resize sert ici a deballer : usdcat veut les textures en fichiers
            _run([str(GLTF), "resize", str(glb), str(w / "m.gltf"),
                  "--width", str(taille), "--height", str(taille)])
            _run(["usdcat", "m.gltf", "-o", "m.usda"], cwd=w)
            _rebind_scenekit_textures(w / "m.usda")   # liaison directe pour SceneKit (#292)
            _inject_subdivision(w / "m.usda")
            _run(["usdzip", "--arkitAsset", "m.usda", "out.usdz"], cwd=w)
            out_dir.mkdir(exist_ok=True)
            shutil.move(str(w / "out.usdz"), str(out))
        return (glb.stem, src_mb, out.stat().st_size / 1e6, "ok")
    except Exception as e:  # noqa: BLE001
        return (glb.stem, src_mb, 0.0, f"ECHEC: {e}")


def main() -> None:
    p = argparse.ArgumentParser(description="GLB alleges -> USDZ ARKit")
    p.add_argument("source", help="repertoire des GLB produits par reatlas_lot.py")
    p.add_argument("--out", default="opti_trellis")
    p.add_argument("--texture-size", type=int, default=1024)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--force", action="store_true")
    args = p.parse_args()

    if not GLTF.exists():
        sys.exit("gltf-transform absent — lancer npm install dans Plant3DGenerator/")
    glbs = sorted(Path(args.source).glob("*.glb"))
    if not glbs:
        sys.exit(f"aucun GLB dans {args.source}")
    out_dir = SCRIPT_DIR / args.out
    out_dir.mkdir(exist_ok=True)

    print(f"{len(glbs)} GLB -> {out_dir}")
    res = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for nom, src, dst, etat in ex.map(
                lambda g: convertir(g, out_dir, args.texture_size, args.force), glbs):
            res.append((nom, src, dst, etat))
            if etat == "ok":
                print(f"  {nom:42} {src:5.2f} -> {dst:5.2f} Mo")
            elif etat == "skip":
                print(f"  {nom:42} deja fait ({dst:.2f} Mo)")
            else:
                print(f"  {nom:42} {etat}")

    ok = [r for r in res if r[3] == "ok"]
    if ok:
        total = sum(r[2] for r in ok)
        print(f"\n{len(ok)} convertis, {total:.0f} Mo au total, moyenne {total/len(ok):.2f} Mo")
    echecs = [r[0] for r in res if r[3].startswith("ECHEC")]
    if echecs:
        print(f"{len(echecs)} echecs : {echecs}")
    sys.exit(1 if echecs else 0)


if __name__ == "__main__":
    main()
