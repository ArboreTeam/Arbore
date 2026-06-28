#!/usr/bin/env python3
"""Render a PNG catalogue thumbnail for each plant from its LIGHT 3D model and
stage it where the backend serves thumbnails (ArboreBackend/models/thumbnails/
<plantId>.png). This way the iOS catalogue shows server PNGs instantly and never
has to download a USDZ just to make a thumbnail.

Reads _thumb_map.json: [{id, model, outlier}, ...] (plantId + opti_output model).

  python render_thumbnails.py [--only-outliers] [--skip-outliers] [--size 1024]
                              [--workers 3] [--force]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
OPTI_DIR = SCRIPT_DIR / "opti_output"
THUMB_DIR = SCRIPT_DIR.parent / "ArboreBackend" / "models" / "thumbnails"


def render_one(entry: dict, size: int, force: bool) -> tuple[str, str]:
    pid, model = entry["id"], entry["model"]
    src = OPTI_DIR / model
    out = THUMB_DIR / f"{pid}.png"
    if out.exists() and not force:
        return (model, "skip")
    if not src.exists():
        return (model, "no-model")
    try:
        subprocess.run(
            ["usdrecord", "--imageWidth", str(size), "--frames", "0:0", str(src), str(out).replace(".png", ".#.png")],
            capture_output=True, text=True, timeout=180,
        )
        # usdrecord writes <name>.0.png — normalize to <id>.png
        framed = THUMB_DIR / f"{pid}.0.png"
        if framed.exists():
            framed.replace(out)
        return (model, "ok" if out.exists() else "fail")
    except subprocess.TimeoutExpired:
        return (model, "timeout")
    except Exception as e:  # noqa: BLE001
        return (model, f"fail:{e}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--size", type=int, default=1024)
    p.add_argument("--workers", type=int, default=3)
    p.add_argument("--only-outliers", action="store_true")
    p.add_argument("--skip-outliers", action="store_true")
    p.add_argument("--force", action="store_true")
    args = p.parse_args()

    entries = json.loads((SCRIPT_DIR / "_thumb_map.json").read_text())
    if args.only_outliers:
        entries = [e for e in entries if e.get("outlier")]
    elif args.skip_outliers:
        entries = [e for e in entries if not e.get("outlier")]

    THUMB_DIR.mkdir(parents=True, exist_ok=True)
    print(f"🖼️  rendering {len(entries)} thumbnail(s) @ {args.size}px → {THUMB_DIR}")
    ok = skip = fail = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for model, status in ex.map(lambda e: render_one(e, args.size, args.force), entries):
            if status == "ok":
                ok += 1
            elif status == "skip":
                skip += 1
            else:
                fail += 1
                print(f"  ⚠️ {model}: {status}")
    print(f"🏁 thumbnails — ok:{ok} skip:{skip} fail:{fail}")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
