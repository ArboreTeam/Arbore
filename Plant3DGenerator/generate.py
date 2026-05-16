#!/usr/bin/env python3
"""Headless CLI for Plant3DGenerator.

For the interactive web UI, run `python server.py` instead.
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

from dotenv import load_dotenv

from meshy_client import MeshyClient
from pipeline import Job, PipelineRunner, make_job

SCRIPT_DIR = Path(__file__).parent
load_dotenv(SCRIPT_DIR / ".env")

OUTPUT_DIR = SCRIPT_DIR / "output"
OUTPUT_DIR.mkdir(exist_ok=True)


def parse_input(path: Path):
    """Parse input.txt — one plant per non-comment line.

    Format: `Common Name | Latin Name | hint | height_m | habit`
      - column 4 (height_m, optional) : real-world height in meters
        forwarded to Meshy via the prompt + `auto_size=True`.
      - column 5 (habit, optional, default "upright") : drives the
        cascade-aware prompt block (cf issue #185). Valid values :
        upright | trailing | arching | bushy. Anything unrecognised
        falls back to "upright".
    """
    plants = []
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) < 2:
                continue
            height_m = 0.0
            if len(parts) >= 4 and parts[3]:
                try:
                    height_m = float(parts[3])
                except ValueError:
                    height_m = 0.0
            habit = parts[4].lower() if len(parts) >= 5 and parts[4] else "upright"
            plants.append({
                "common": parts[0],
                "latin": parts[1],
                "hint": parts[2] if len(parts) >= 3 else "",
                "height_m": height_m,
                "habit": habit,
            })
    return plants


def log_event(job: Job) -> None:
    sp = job.stages["preview"]
    sr = job.stages["refine"]
    ts = time.strftime("%H:%M:%S")
    line = (f"[{ts}] {job.latin:<32} "
            f"preview={sp.status}/{sp.progress:>3}% "
            f"refine={sr.status}/{sr.progress:>3}%")
    if sp.task_id:
        line += f" p={sp.task_id[:8]}"
    if sr.task_id:
        line += f" r={sr.task_id[:8]}"
    print(line, flush=True)


def main() -> None:
    p = argparse.ArgumentParser(description="Meshy plant generator (headless)")
    p.add_argument("--input", default=str(SCRIPT_DIR / "input.txt"))
    p.add_argument("--all", action="store_true",
                   help="Process every line (default: only the first)")
    p.add_argument("--preview-only", action="store_true",
                   help="Skip refine step — cheaper, no textures")
    p.add_argument("--dry-run", action="store_true",
                   help="Parse input and print what would run, no API calls")
    args = p.parse_args()

    api_key = os.getenv("MESHY_API_KEY")
    if not api_key:
        sys.exit("❌ MESHY_API_KEY not set (copy .env.example → .env)")

    plants = parse_input(Path(args.input))
    if not plants:
        sys.exit("❌ No plants found in input")
    if not args.all:
        plants = plants[:1]
        print("🧪 single-plant mode (pass --all to process every line)")

    print(f"📋 {len(plants)} plant(s):")
    for pl in plants:
        print(f"   • {pl['common']} ({pl['latin']})")
    # Meshy pricing (from docs): low poly preview = 20 credits, refine = 10 credits
    est = 20 if args.preview_only else 30
    print(f"💰 ~{est * len(plants)} credits estimated")

    if args.dry_run:
        print("🏁 dry-run, exiting")
        return

    client = MeshyClient(api_key)
    runner = PipelineRunner(client, OUTPUT_DIR, on_event=log_event)

    ok = 0
    for pl in plants:
        job = make_job(pl["common"], pl["latin"], pl["hint"],
                       height_m=pl["height_m"], habit=pl["habit"])
        runner.run(job, preview_only=args.preview_only)
        last_stage = "preview" if args.preview_only else "refine"
        if job.stages[last_stage].status == "done":
            ok += 1

    print(f"🏁 done — {ok}/{len(plants)} succeeded")
    sys.exit(0 if ok == len(plants) else 1)


if __name__ == "__main__":
    main()
