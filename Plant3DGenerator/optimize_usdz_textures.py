#!/usr/bin/env python3
"""Texture-only USDZ optimizer (no GLB needed).

For models whose weight is in 4K PBR textures rather than mesh (legacy lowpoly
plants, text-to-3D lowpoly outputs), this just downsizes the embedded textures
and repackages — mesh untouched. usdzip keeps the ARKit packaging; the usdc
(with subdivisionScheme=none) is preserved as-is.

  python optimize_usdz_textures.py --in <dir> --out <dir> [--size 1024]
                                   [--workers 4] [--force]
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

IMG_EXT = {".jpg", ".jpeg", ".png"}


def optimize_one(usdz: Path, out_dir: Path, size: int, force: bool) -> tuple[str, float, float, str]:
    out = out_dir / usdz.name
    src_mb = usdz.stat().st_size / 1e6
    if out.exists() and not force:
        return (usdz.name, src_mb, out.stat().st_size / 1e6, "skip")
    try:
        with tempfile.TemporaryDirectory() as td:
            w = Path(td)
            with zipfile.ZipFile(usdz) as zf:
                zf.extractall(w)
            # resize every embedded texture (in place) to max `size` px
            for img in list(w.rglob("*")):
                if img.suffix.lower() in IMG_EXT:
                    subprocess.run(["sips", "-Z", str(size), str(img)],
                                   capture_output=True, timeout=60)
            roots = list(w.rglob("*.usdc")) + list(w.rglob("*.usda"))
            if not roots:
                return (usdz.name, src_mb, 0.0, "no-usd-root")
            root = roots[0]
            out_dir.mkdir(parents=True, exist_ok=True)
            tmp_out = w / "out.usdz"
            subprocess.run(["usdzip", "--arkitAsset", root.name, str(tmp_out)],
                           cwd=w, capture_output=True, text=True, timeout=180, check=True)
            shutil.move(str(tmp_out), str(out))
        return (usdz.name, src_mb, out.stat().st_size / 1e6, "ok")
    except Exception as e:  # noqa: BLE001
        return (usdz.name, src_mb, 0.0, f"FAIL:{e}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--in", dest="indir", required=True)
    p.add_argument("--out", dest="outdir", required=True)
    p.add_argument("--size", type=int, default=1024)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--force", action="store_true")
    args = p.parse_args()

    src = sorted(Path(args.indir).glob("*.usdz"))
    out_dir = Path(args.outdir)
    if not src:
        sys.exit(f"❌ no usdz in {args.indir}")
    print(f"🎨 texture-optimizing {len(src)} usdz @ {args.size}px → {out_dir}")
    results = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for r in ex.map(lambda f: optimize_one(f, out_dir, args.size, args.force), src):
            name, s, d, status = r
            results.append(r)
            if status == "ok":
                print(f"✅ {name:42} {s:5.1f} → {d:4.1f} MB (÷{s/d:.1f})")
            elif status == "skip":
                print(f"⏭️  {name:42} exists")
            else:
                print(f"❌ {name:42} {status}")
    ok = [r for r in results if r[3] == "ok"]
    if ok:
        ts, td = sum(r[1] for r in ok), sum(r[2] for r in ok)
        print(f"\n🏁 {len(ok)} done — {ts:.0f} → {td:.0f} MB (÷{ts/td:.1f}), avg {td/len(ok):.1f} MB")
    sys.exit(1 if any(r[3].startswith('FAIL') for r in results) else 0)


if __name__ == "__main__":
    main()
