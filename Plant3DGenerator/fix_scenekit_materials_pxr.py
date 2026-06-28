#!/usr/bin/env python3
"""SceneKit material rebinder for glTF-roundtrip USDZ — pxr (USD) version.

Same fix as fix_scenekit_materials.py, but uses ONLY the `pxr` module
(`pip install usd-core`) — no usdcat/usdzip CLI — so it runs on a server
without Xcode/USD CLI (e.g. the Fedora VPS), in place, with no file transfer.

It rewrites every UsdUVTexture `inputs:file` that is *connected* to a Material
interface input into a *direct* asset value, so SceneKit's USD importer binds
the texture (these plants render grey in AR otherwise). Geometry, UV transforms,
colorspaces and embedded textures are untouched.

Usage:
  python3 fix_pxr.py --check <a.usdz> [b.usdz ...]
  python3 fix_pxr.py <in.usdz> <out.usdz>
  python3 fix_pxr.py --inplace --dir <dir> [--backup <dir>] [--workers N]
"""
from __future__ import annotations

import shutil
import sys
import tempfile
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from pxr import Usd, UsdShade, UsdUtils  # noqa: E402


def _count_connected_textures(usdz: Path) -> int:
    try:
        stage = Usd.Stage.Open(str(usdz))
    except Exception:
        return -1
    if not stage:
        return -1
    n = 0
    for prim in stage.Traverse():
        sh = UsdShade.Shader(prim)
        if not sh or sh.GetIdAttr().Get() != "UsdUVTexture":
            continue
        inp = sh.GetInput("file")
        if inp and inp.GetAttr().GetConnections():
            n += 1
    return n


def _rewrite_extracted(work: Path) -> int:
    roots = sorted(list(work.rglob("*.usdc")) + list(work.rglob("*.usda")))
    fixed = 0
    for root in roots:
        stage = Usd.Stage.Open(str(root))
        if not stage:
            continue
        changed = False
        for prim in stage.Traverse():
            sh = UsdShade.Shader(prim)
            if not sh or sh.GetIdAttr().Get() != "UsdUVTexture":
                continue
            inp = sh.GetInput("file")
            if not inp:
                continue
            attr = inp.GetAttr()
            conns = attr.GetConnections()
            if not conns:
                continue
            src = stage.GetAttributeAtPath(conns[0])
            val = src.Get() if src else None
            if val is None:
                continue
            attr.ClearConnections()
            attr.Set(val)          # set the resolved @asset@ path directly
            fixed += 1
            changed = True
        if changed:
            stage.GetRootLayer().Save()
    return fixed


def fix_usdz(src: Path, dst: Path) -> tuple[bool, str]:
    try:
        with tempfile.TemporaryDirectory() as td:
            w = Path(td)
            with zipfile.ZipFile(src) as zf:
                zf.extractall(w)
            roots = sorted(list(w.rglob("*.usdc")) + list(w.rglob("*.usda")))
            if not roots:
                return False, "no usd root"
            n = _rewrite_extracted(w)
            if n == 0:
                return False, "nothing to fix (already direct?)"
            out_tmp = w / "_out.usdz"
            # CreateNewARKitUsdzPackage resolves relative deps against CWD; run from w.
            import os
            cwd = os.getcwd()
            try:
                os.chdir(w)
                ok = UsdUtils.CreateNewARKitUsdzPackage(roots[0].name, "_out.usdz")
            finally:
                os.chdir(cwd)
            if not ok or not out_tmp.exists():
                return False, "usdz repackage failed"
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(out_tmp), str(dst))
        return True, f"fixed {n} texture binding(s)"
    except Exception as e:  # noqa: BLE001
        return False, f"{type(e).__name__}: {e}"


def main() -> int:
    a = sys.argv[1:]
    if a and a[0] == "--check":
        for f in a[1:]:
            print(f"{f}: {_count_connected_textures(Path(f))} connected UsdUVTexture(s)")
        return 0
    if "--inplace" in a and "--dir" in a:
        d = Path(a[a.index("--dir") + 1])
        backup = Path(a[a.index("--backup") + 1]) if "--backup" in a else d.parent / (d.name + "_greybak")
        workers = int(a[a.index("--workers") + 1]) if "--workers" in a else 6
        files = sorted(d.glob("*.usdz"))
        with ThreadPoolExecutor(max_workers=workers) as ex:
            counts = dict(zip(files, ex.map(_count_connected_textures, files)))
        bad = [f for f in files if counts[f] > 0]
        good = [f for f in files if counts[f] == 0]
        err = [f for f in files if counts[f] < 0]
        backup.mkdir(parents=True, exist_ok=True)
        print(f"{len(files)} usdz → {len(bad)} to fix, {len(good)} already direct, {len(err)} unreadable")
        if err:
            print("⚠️  unreadable: " + ", ".join(f.name for f in err))

        def _do(f: Path):
            shutil.copy2(f, backup / f.name)                 # backup grey original
            ok, msg = fix_usdz(f, f.with_suffix(".usdz.tmpfix"))
            if ok:
                shutil.move(str(f.with_suffix(".usdz.tmpfix")), str(f))
            return f, ok, msg

        nok = 0
        with ThreadPoolExecutor(max_workers=workers) as ex:
            for f, ok, msg in ex.map(_do, bad):
                print(("✅ " if ok else "❌ ") + f"{f.name:50} {msg}")
                nok += ok
        print(f"🏁 fixed {nok}/{len(bad)} in place; backups in {backup}")
        return 0 if nok == len(bad) else 1
    if len(a) != 2:
        print(__doc__)
        return 2
    ok, msg = fix_usdz(Path(a[0]), Path(a[1]))
    print(("✅ " if ok else "❌ ") + msg)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
