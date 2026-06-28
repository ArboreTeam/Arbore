#!/usr/bin/env python3
"""Re-generate the feathery/fragmented plants that mesh-decimation couldn't
shrink (ferns, asparagus, pilea, spider plant, sedum) as clean LOW-POLY models
via text-to-3D, writing them straight into opti_output/ as the lightweight LOD.

The dense image-to-3D originals stay untouched in output/ (the "heavy" LOD).
Reads _regen_outliers.json: [{stem, species, prompt}, ...].

  python regen_outliers.py [--workers 4] [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from dotenv import load_dotenv

from meshy_client import MeshyClient
from pipeline import PipelineRunner, make_job

SCRIPT_DIR = Path(__file__).parent
load_dotenv(SCRIPT_DIR / ".env")
OPTI_DIR = SCRIPT_DIR / "opti_output"
OPTI_DIR.mkdir(exist_ok=True)


def regen_one(client: MeshyClient, t: dict) -> tuple[str, str]:
    stem = t["stem"]
    out = OPTI_DIR / f"{stem}.usdz"
    job = make_job(common=stem, latin=t["species"], hint=t.get("prompt", ""))
    job.job_id = stem  # so files are named opti_output/<stem>.{glb,usdz}
    ts = time.strftime("%H:%M:%S")
    print(f"[{ts}] {stem:42} text-to-3D lowpoly ({t['species']})", flush=True)
    try:
        runner = PipelineRunner(client, OPTI_DIR)
        runner.run(job, preview_only=False)
        if job.stages["refine"].status == "done" and out.exists():
            mb = out.stat().st_size / 1e6
            print(f"✅ {stem:42} → {mb:.1f} MB", flush=True)
            return (stem, "ok")
        err = job.stages["refine"].error or job.stages["preview"].error or "unknown"
        print(f"❌ {stem:42} {err}", flush=True)
        return (stem, "fail")
    except Exception as e:  # noqa: BLE001
        print(f"❌ {stem:42} {e}", flush=True)
        return (stem, "fail")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    targets = json.loads((SCRIPT_DIR / "_regen_outliers.json").read_text())
    print(f"📋 {len(targets)} outlier(s) → opti_output/ (text-to-3D lowpoly)")
    for t in targets:
        print(f"   • {t['stem']} ({t['species']})")
    print(f"💰 ~{30 * len(targets)} credits estimated")
    if args.dry_run:
        print("🏁 dry-run")
        return

    api_key = os.getenv("MESHY_API_KEY")
    if not api_key:
        sys.exit("❌ MESHY_API_KEY not set")
    client = MeshyClient(api_key)

    ok = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for _, status in ex.map(lambda t: regen_one(client, t), targets):
            if status == "ok":
                ok += 1
    print(f"🏁 done — {ok}/{len(targets)} regenerated into opti_output/")
    sys.exit(0 if ok == len(targets) else 1)


if __name__ == "__main__":
    main()
