#!/usr/bin/env python3
"""Fix glTF-roundtrip USDZ so SceneKit (ARSCNView) binds plant textures.

`optimize_models.py` runs `gltf-transform ... -> usdcat (glTF->USD)`, which emits
materials where every UsdUVTexture reads its image via
    asset inputs:file.connect = </.../MaterialX.inputs:<channel>Texture>
i.e. the real asset path is declared once on the Material's *interface input*
and the shaders read it through a connection. SceneKit's USD importer (Model I/O,
used by SCNScene(url:) for .usdz in the AR placement view) does NOT follow that
connection, so it falls back to its default GREY material. RealityKit, Hydra and
`usdrecord` (the backend thumbnail PNGs) DO follow it — which is why such plants
look correct in the catalog but grey in AR.

This rewrites each `asset inputs:file.connect = <Mat.inputs:KEY>` into the
resolved direct `asset inputs:file = @path@`, leaving everything else untouched
(geometry, UV `UsdTransform2d` V-flip, colorspaces, the NodeGraph wrapper, the
embedded textures). Toolchain: usdcat + usdzip only (no pxr needed), mirroring
the existing usdz_patch.py.

Usage:
  python3 fix_scenekit_materials.py <in.usdz> <out.usdz>      # one file
  python3 fix_scenekit_materials.py --check <file.usdz>       # report only
  python3 fix_scenekit_materials.py --dir <in_dir> <out_dir>  # batch
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# `asset inputs:file.connect = </m/Materials/Material0.inputs:baseColorTexture>`
_CONNECT_RE = re.compile(
    r'^(?P<indent>\s*)asset inputs:file\.connect\s*=\s*<(?P<path>[^>]+)\.inputs:(?P<key>\w+)>\s*$'
)
# `asset inputs:baseColorTexture = @0/baseColor_1.jpg@`  (Material interface input)
_IFACE_RE = re.compile(r'^\s*asset inputs:(?P<key>\w+)\s*=\s*(?P<val>@[^@]+@)\s*$')
_MAT_RE = re.compile(r'def Material "(?P<name>[^"]+)"')


def _fix_usda(text: str) -> tuple[str, int, int]:
    """Return (new_text, n_fixed, n_unresolved)."""
    # 1) Map (material_name, interface_key) -> @asset@
    iface: dict[tuple[str, str], str] = {}
    cur_mat: str | None = None
    for line in text.splitlines():
        mm = _MAT_RE.search(line)
        if mm:
            cur_mat = mm.group("name")
            continue
        im = _IFACE_RE.match(line)
        if im and cur_mat and im.group("key").endswith("Texture"):
            iface[(cur_mat, im.group("key"))] = im.group("val")

    # 2) Rewrite each file.connect to the resolved direct asset path.
    out: list[str] = []
    fixed = unresolved = 0
    for line in text.splitlines():
        cm = _CONNECT_RE.match(line)
        if cm:
            mat = cm.group("path").rstrip("/").split("/")[-1]
            key = cm.group("key")
            val = iface.get((mat, key))
            if val is None:  # fallback: unique key across materials
                cands = {v for (m, k), v in iface.items() if k == key}
                val = next(iter(cands)) if len(cands) == 1 else None
            if val is not None:
                out.append(f'{cm.group("indent")}asset inputs:file = {val}')
                fixed += 1
                continue
            unresolved += 1
        out.append(line)
    new_text = "\n".join(out) + ("\n" if text.endswith("\n") else "")
    return new_text, fixed, unresolved


def _count_connects(usdz: Path) -> int:
    try:
        r = subprocess.run(["usdcat", str(usdz)], capture_output=True, text=True, timeout=180)
        return r.stdout.count("inputs:file.connect")
    except Exception:
        return -1


def fix_usdz(src: Path, dst: Path) -> tuple[bool, str]:
    if not shutil.which("usdcat") or not shutil.which("usdzip"):
        return False, "usdcat/usdzip not found"
    try:
        with tempfile.TemporaryDirectory() as td:
            w = Path(td)
            with zipfile.ZipFile(src) as zf:
                zf.extractall(w)
            roots = sorted(list(w.rglob("*.usdc")) + list(w.rglob("*.usda")))
            if not roots:
                return False, "no usd root"
            total_fixed = total_unresolved = 0
            for usd in roots:
                usda = usd.with_suffix(".fix.usda")
                subprocess.run(["usdcat", str(usd), "-o", str(usda)],
                               check=True, capture_output=True, timeout=120)
                text = usda.read_text()
                new_text, fixed, unresolved = _fix_usda(text)
                total_fixed += fixed
                total_unresolved += unresolved
                if fixed:
                    usda.write_text(new_text)
                    subprocess.run(["usdcat", str(usda), "-o", str(usd)],
                                   check=True, capture_output=True, timeout=120)
                usda.unlink(missing_ok=True)
            if total_fixed == 0:
                return False, f"nothing to fix (already direct?), unresolved={total_unresolved}"
            root = roots[0]
            tmp_out = w / "out.usdz"
            subprocess.run(["usdzip", "--arkitAsset", root.name, str(tmp_out)],
                           cwd=w, check=True, capture_output=True, text=True, timeout=180)
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(tmp_out), str(dst))
        return True, f"fixed {total_fixed} texture binding(s), unresolved={total_unresolved}"
    except subprocess.CalledProcessError as e:
        return False, f"{e.cmd[0]} failed: {(e.stderr or b'').decode()[-200:] if isinstance(e.stderr, bytes) else e.stderr}"
    except Exception as e:  # noqa: BLE001
        return False, f"{type(e).__name__}: {e}"


def main() -> int:
    a = sys.argv[1:]
    if a and a[0] == "--check":
        for f in a[1:]:
            print(f"{f}: {_count_connects(Path(f))} inputs:file.connect")
        return 0
    if a and a[0] == "--dir":
        in_dir, out_dir = Path(a[1]), Path(a[2])
        workers = 6
        if "--workers" in a:
            workers = int(a[a.index("--workers") + 1])
        files = sorted(in_dir.glob("*.usdz"))
        # Classify (parallel): a model needs fixing iff its USD has file.connect.
        with ThreadPoolExecutor(max_workers=workers) as ex:
            counts = list(ex.map(_count_connects, files))
        bad = [f for f, c in zip(files, counts) if c > 0]
        good = [f for f, c in zip(files, counts) if c == 0]
        err = [f for f, c in zip(files, counts) if c < 0]
        print(f"{len(files)} usdz → {len(bad)} need fixing, {len(good)} already direct, {len(err)} unreadable")
        if err:
            print("⚠️  unreadable: " + ", ".join(f.name for f in err))
        # Fix the grey ones (parallel). out_dir ends up containing ONLY fixed models.
        def _do(f):
            return f, fix_usdz(f, out_dir / f.name)
        nok = 0
        with ThreadPoolExecutor(max_workers=workers) as ex:
            for f, (ok, msg) in ex.map(_do, bad):
                print(("✅ " if ok else "❌ ") + f"{f.name:50} {msg}")
                nok += ok
        print(f"🏁 fixed {nok}/{len(bad)} (out_dir has only the fixed models)")
        return 0 if nok == len(bad) else 1
    if len(a) != 2:
        print(__doc__)
        return 2
    ok, msg = fix_usdz(Path(a[0]), Path(a[1]))
    print(("✅ " if ok else "❌ ") + msg)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
