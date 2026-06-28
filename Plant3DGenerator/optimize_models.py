#!/usr/bin/env python3
"""Optimize Meshy-generated 3D models for mobile AR.

Meshy image-to-3D returns very dense meshes (~800k+ triangles) and large
textures, so a single .usdz can be 30–130 MB — far too heavy to download/render
on iOS. This decimates the mesh and downsizes textures, writing optimized .usdz
files to opti_output/ WITHOUT touching the originals in output/.

Pipeline per model (from the source GLB):
  gltf-transform weld → simplify → resize (unpacked .gltf, textures as files)
  → usdcat .gltf → .usda → inject subdivisionScheme="none" (iOS ARView)
  → usdzip --arkitAsset → opti_output/<name>.usdz

Validated: Monstera 29 MB → 3 MB (~9x), visually near-identical.

  python optimize_models.py [--ratio 0.1] [--error 0.01] [--texture-size 1024]
                            [--workers 4] [--limit N] [--only NAME] [--force]
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
SRC_DIR = SCRIPT_DIR / "output"
OUT_DIR = SCRIPT_DIR / "opti_output"
GLTF = SCRIPT_DIR / "node_modules" / ".bin" / "gltf-transform"

_MESH_RE = re.compile(r'(def Mesh "[^"]+"\s*\n\s*\{\s*\n)')


def _run(cmd: list[str], cwd: Path | None = None) -> None:
    res = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=600)
    if res.returncode != 0:
        raise RuntimeError(f"{cmd[0]} {cmd[1] if len(cmd) > 1 else ''} failed: "
                           f"{(res.stderr or res.stdout)[-300:]}")


def _inject_subdivision(usda_path: Path) -> None:
    t = usda_path.read_text()
    if "subdivisionScheme" in t:
        return
    t = _MESH_RE.sub(lambda m: m.group(1) + '        uniform token subdivisionScheme = "none"\n', t)
    usda_path.write_text(t)


def optimize_one(glb: Path, args) -> tuple[str, float, float, str]:
    name = glb.stem
    out = OUT_DIR / f"{name}.usdz"
    src_mb = glb.stat().st_size / 1e6
    if out.exists() and not args.force:
        return (name, src_mb, out.stat().st_size / 1e6, "skip")
    try:
        with tempfile.TemporaryDirectory() as td:
            w = Path(td)
            _run([str(GLTF), "weld", str(glb), str(w / "1.glb")])
            _run([str(GLTF), "simplify", str(w / "1.glb"), str(w / "2.glb"),
                  "--ratio", str(args.ratio), "--error", str(args.error),
                  "--lock-border", "false"])
            # resize, emitting an UNPACKED .gltf so textures land as files usdcat can read
            _run([str(GLTF), "resize", str(w / "2.glb"), str(w / "m.gltf"),
                  "--width", str(args.texture_size), "--height", str(args.texture_size)])
            _run(["usdcat", "m.gltf", "-o", "m.usda"], cwd=w)
            _inject_subdivision(w / "m.usda")
            _run(["usdzip", "--arkitAsset", "m.usda", "out.usdz"], cwd=w)
            OUT_DIR.mkdir(exist_ok=True)
            shutil.move(str(w / "out.usdz"), str(out))
        return (name, src_mb, out.stat().st_size / 1e6, "ok")
    except Exception as e:  # noqa: BLE001
        return (name, src_mb, 0.0, f"FAIL: {e}")


def main() -> None:
    p = argparse.ArgumentParser(description="Optimize Meshy 3D models for mobile AR")
    p.add_argument("--ratio", type=float, default=0.1, help="simplify target vertex ratio (lower = smaller)")
    p.add_argument("--error", type=float, default=0.01, help="simplify max error (higher = smaller)")
    p.add_argument("--texture-size", type=int, default=1024)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--limit", type=int, default=0)
    p.add_argument("--only", default="", help="optimize a single model by stem (substring)")
    p.add_argument("--force", action="store_true")
    args = p.parse_args()

    if not GLTF.exists():
        sys.exit("❌ gltf-transform not installed — run: npm install (in Plant3DGenerator/)")

    glbs = sorted(SRC_DIR.glob("*.glb"))
    if args.only:
        glbs = [g for g in glbs if args.only.lower() in g.stem.lower()]
    if args.limit:
        glbs = glbs[: args.limit]
    if not glbs:
        sys.exit("❌ no source GLB found in output/")

    print(f"⚙️  optimizing {len(glbs)} model(s) → opti_output/ (ratio={args.ratio}, tex={args.texture_size}, {args.workers} workers)")
    results = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for r in ex.map(lambda g: optimize_one(g, args), glbs):
            name, src, dst, status = r
            results.append(r)
            if status == "ok":
                print(f"✅ {name:42} {src:6.1f} → {dst:5.2f} MB  (÷{src/dst:.1f})" if dst else f"✅ {name}")
            elif status == "skip":
                print(f"⏭️  {name:42} exists ({dst:.2f} MB)")
            else:
                print(f"❌ {name:42} {status}")

    ok = [r for r in results if r[3] == "ok"]
    if ok:
        tot_src = sum(r[1] for r in ok)
        tot_dst = sum(r[2] for r in ok)
        print(f"\n🏁 {len(ok)} optimized — total {tot_src:.0f} MB → {tot_dst:.0f} MB "
              f"(÷{tot_src/tot_dst:.1f}), avg {tot_dst/len(ok):.1f} MB")
    fails = [r for r in results if r[3].startswith("FAIL")]
    if fails:
        print(f"⚠️  {len(fails)} failed: {[r[0] for r in fails][:5]}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
