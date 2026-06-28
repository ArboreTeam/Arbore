#!/usr/bin/env python3
"""Headless Image-to-3D generator.

Turns real plant photos into 3D models via Meshy image-to-3D (v1). Reads a
manifest produced by the (local) BotanicScraper, or a single --image/--name
pair. Downloads GLB + USDZ into output/ and patches the USDZ for iOS ARView
(same subdivisionScheme fix as the text-to-3D pipeline).

Examples:
  # one-off from a public image URL
  python generate_from_images.py --image https://…/monstera.png --name "Monstera deliciosa"

  # batch from the scraper manifest (estimate first)
  python generate_from_images.py --manifest ../BotanicScraper/data/manifest.json --all --dry-run
  python generate_from_images.py --manifest ../BotanicScraper/data/manifest.json --all
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

from dotenv import load_dotenv

from meshy_image_client import MeshyImageClient, image_to_data_uri
from pipeline import safe_filename
from usdz_patch import patch_usdz_subdivision

SCRIPT_DIR = Path(__file__).parent
load_dotenv(SCRIPT_DIR / ".env")

OUTPUT_DIR = SCRIPT_DIR / "output"
OUTPUT_DIR.mkdir(exist_ok=True)


def load_jobs(args) -> list[dict]:
    """Normalize inputs into a list of {name, image, texture_prompt, stem}."""
    if args.image:
        name = args.name or "plant"
        return [{
            "name": name,
            "image": args.image,
            "texture_prompt": args.texture_prompt or "",
            "stem": safe_filename(name),
        }]

    if not args.manifest:
        sys.exit("❌ pass --manifest <path> or --image <url|file> --name <latin>")

    manifest_path = Path(args.manifest)
    if not manifest_path.is_absolute():
        manifest_path = (Path.cwd() / manifest_path).resolve()
    if not manifest_path.exists():
        sys.exit(f"❌ manifest not found: {manifest_path}")

    manifest = json.loads(manifest_path.read_text())
    base = manifest_path.parent  # data/ — local image paths are relative to a plant dir
    jobs = []
    for p in manifest.get("plants", []):
        if not p.get("include", True):
            continue
        meshy = p.get("meshy", {})
        image = meshy.get("imageRemote")
        # Fall back to a local file (encoded as data URI) if no public URL.
        if not image and meshy.get("imageLocal"):
            local = base / p["slug"] / meshy["imageLocal"]
            if local.exists():
                image = image_to_data_uri(local)
        if not image:
            print(f"⚠️  no image for {p.get('name')}, skipping")
            continue
        stem = Path(p.get("modelFilename") or f"{safe_filename(p['name'])}.usdz").stem
        jobs.append({
            "name": p["name"],
            "image": image,
            "texture_prompt": meshy.get("texturePrompt", ""),
            "stem": stem,
        })
    return jobs


def generate_one(client: MeshyImageClient, job: dict, *, no_texture_prompt: bool) -> bool:
    name, stem = job["name"], job["stem"]
    usdz_out = OUTPUT_DIR / f"{stem}.usdz"
    if usdz_out.exists():
        print(f"⏭️  {stem}.usdz exists, skipping")
        return True

    ts = time.strftime("%H:%M:%S")
    src = job["image"][:48] + ("…" if len(job["image"]) > 48 else "")
    print(f"[{ts}] {name:<28} → image-to-3D ({src})", flush=True)
    try:
        task_id = client.create(
            job["image"],
            texture_prompt="" if no_texture_prompt else job.get("texture_prompt", ""),
        )

        def on_progress(status, progress, _data):
            print(f"    {stem}: {status} {progress}%", flush=True)

        data = client.poll(task_id, on_progress=on_progress)
        urls = data.get("model_urls") or {}
        if urls.get("glb"):
            client.download(urls["glb"], OUTPUT_DIR / f"{stem}.glb")
        if urls.get("usdz"):
            client.download(urls["usdz"], usdz_out)
            patch_usdz_subdivision(usdz_out)
        print(f"✅ {stem} — {data.get('consumed_credits', '?')} credits", flush=True)
        return urls.get("usdz") is not None
    except Exception as e:  # noqa: BLE001 — log and continue the batch
        print(f"❌ {stem} failed: {e}", flush=True)
        return False


def main() -> None:
    p = argparse.ArgumentParser(description="Meshy image-to-3D generator (headless)")
    p.add_argument("--manifest", help="BotanicScraper data/manifest.json")
    p.add_argument("--image", help="single image URL or local file path")
    p.add_argument("--name", help="latin/common name for the single image")
    p.add_argument("--texture-prompt", default="", help="texture prompt for the single image")
    p.add_argument("--no-texture-prompt", action="store_true",
                   help="skip texture prompts (saves 10 credits/plant)")
    p.add_argument("--all", action="store_true", help="process every manifest plant (default: first)")
    p.add_argument("--limit", type=int, default=0, help="cap number of plants")
    p.add_argument("--workers", type=int, default=5,
                   help="concurrent generations (keep <= your Meshy tier's concurrent-task limit)")
    p.add_argument("--dry-run", action="store_true", help="list jobs + credit estimate, no API calls")
    args = p.parse_args()

    api_key = os.getenv("MESHY_API_KEY")
    if not api_key and not args.dry_run:
        sys.exit("❌ MESHY_API_KEY not set (copy .env.example → .env)")

    jobs = load_jobs(args)
    # Dedup by output stem so name-collisions (e.g. two "Areca" SKUs → Areca.usdz)
    # don't generate the same model twice under concurrency.
    seen_stems: set[str] = set()
    deduped = []
    for j in jobs:
        if j["stem"] in seen_stems:
            continue
        seen_stems.add(j["stem"])
        deduped.append(j)
    if len(deduped) != len(jobs):
        print(f"🔁 deduped {len(jobs) - len(deduped)} duplicate model name(s)")
    jobs = deduped
    if not jobs:
        sys.exit("❌ no jobs to run")
    if not args.image and not args.all:
        jobs = jobs[:1]
        print("🧪 single-plant mode (pass --all to process every manifest plant)")
    if args.limit:
        jobs = jobs[: args.limit]

    # image-to-3D is 30 credits; a texture_prompt is free (only a texture_image_url
    # guidance would add 10). Confirmed: the test Monstera consumed 30.
    per = 30
    print(f"📋 {len(jobs)} plant(s):")
    for j in jobs:
        print(f"   • {j['name']} → {j['stem']}.usdz")
    print(f"💰 ~{per * len(jobs)} credits estimated")

    if args.dry_run:
        print("🏁 dry-run, exiting")
        return

    client = MeshyImageClient(api_key)
    workers = max(1, args.workers)
    print(f"⚙️  generating with {workers} concurrent worker(s)")
    ok = 0
    if workers == 1:
        for j in jobs:
            if generate_one(client, j, no_texture_prompt=args.no_texture_prompt):
                ok += 1
    else:
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=workers) as ex:
            futures = [ex.submit(generate_one, client, j, no_texture_prompt=args.no_texture_prompt) for j in jobs]
            for fut in futures:
                if fut.result():
                    ok += 1
    print(f"🏁 done — {ok}/{len(jobs)} succeeded")
    sys.exit(0 if ok == len(jobs) else 1)


if __name__ == "__main__":
    main()
