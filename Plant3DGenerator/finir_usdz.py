#!/usr/bin/env python3
"""Moitié aval de `optimize_models.py` : du .gltf décimé au .usdz ARKit.

Pourquoi ce script existe séparément — la décimation (`gltf-transform weld /
simplify / resize`) est du Node pur et tourne très bien sur l'hôte de
l'atelier, alors que `usdcat` et `usdzip` viennent avec Xcode et n'existent
que sur un Mac. Rapatrier les maillages coupés entiers coûterait 13 Go ; ne
rapatrier que le résultat décimé en coûte 6, et ce script reprend là où
l'hôte s'arrête.

Il n'invente rien : il appelle les fonctions de `optimize_models.py`, dont le
réliage direct des textures sans lequel SceneKit rend des plantes grises
(#292), pour que les deux moitiés restent une seule chaîne.

    python3 finir_usdz.py --entree <dir> --sortie <dir> [--suffixe _potless]

`--entree` contient un sous-répertoire par plante, chacun portant le `m.gltf`,
son `m.bin` et ses textures. Chaque plante donne `<nom><suffixe>.usdz`.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from optimize_models import _inject_subdivision, _rebind_scenekit_textures  # noqa: E402


def convertir(dossier: Path, sortie: Path, suffixe: str, force: bool) -> tuple[str, str, float]:
    """Rend (nom, état, taille en Mo)."""
    nom = dossier.name
    cible = sortie / f"{nom}{suffixe}.usdz"
    if cible.exists() and not force:
        return (nom, "deja", cible.stat().st_size / 1e6)
    gltf = dossier / "m.gltf"
    if not gltf.exists():
        return (nom, "pas de m.gltf", 0.0)
    # Une absence de m.bin passe inaperçue à la conversion et donne un USDZ
    # sans géométrie : on refuse plutôt que de livrer une plante vide.
    if not (dossier / "m.bin").exists():
        return (nom, "pas de m.bin — geometrie absente", 0.0)
    try:
        with tempfile.TemporaryDirectory() as td:
            w = Path(td)
            for f in dossier.iterdir():
                if f.is_file():
                    shutil.copy2(f, w / f.name)
            subprocess.run(["usdcat", "m.gltf", "-o", "m.usda"], cwd=w,
                           capture_output=True, text=True, timeout=900, check=True)
            _rebind_scenekit_textures(w / "m.usda")
            _inject_subdivision(w / "m.usda")
            subprocess.run(["usdzip", "--arkitAsset", "m.usda", "out.usdz"], cwd=w,
                           capture_output=True, text=True, timeout=900, check=True)
            sortie.mkdir(parents=True, exist_ok=True)
            shutil.move(str(w / "out.usdz"), str(cible))
        return (nom, "ok", cible.stat().st_size / 1e6)
    except subprocess.CalledProcessError as e:
        return (nom, f"ECHEC {(e.stderr or '')[:90]}", 0.0)
    except Exception as e:  # noqa: BLE001
        return (nom, f"ECHEC {e}", 0.0)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--entree", required=True, type=Path)
    ap.add_argument("--sortie", required=True, type=Path)
    ap.add_argument("--suffixe", default="_potless")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--supprimer-entree", action="store_true",
                    help="efface le dossier source une fois la plante convertie (disque serre)")
    a = ap.parse_args()

    dossiers = sorted(d for d in a.entree.iterdir() if d.is_dir())
    ok = rates = 0
    for i, d in enumerate(dossiers, 1):
        nom, etat, mo = convertir(d, a.sortie, a.suffixe, a.force)
        print(f"[{i}/{len(dossiers)}] {nom[:46]:46} {etat:34} {mo:6.1f} Mo", flush=True)
        if etat in ("ok", "deja"):
            ok += 1
            if a.supprimer_entree and etat == "ok":
                shutil.rmtree(d)
        else:
            rates += 1
    print(f"\n{ok} converties, {rates} en echec")
    return 1 if rates else 0


if __name__ == "__main__":
    raise SystemExit(main())
