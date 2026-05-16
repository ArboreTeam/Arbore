"""Job + PipelineRunner: orchestrates the Meshy flow and emits state events."""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

from meshy_client import MeshyClient
from usdz_patch import patch_usdz_subdivision


@dataclass
class StageState:
    status: str = "idle"      # idle | running | done | failed
    progress: int = 0
    task_id: str = ""
    error: str = ""
    started_at: float = 0.0
    finished_at: float = 0.0
    glb_file: str = ""        # relative filename inside output/
    usdz_file: str = ""


@dataclass
class Job:
    job_id: str
    common: str
    latin: str
    hint: str
    prompt: str
    texture_prompt: str
    stages: dict = field(default_factory=dict)
    final_glb: str = ""
    final_usdz: str = ""

    def __post_init__(self):
        if not self.stages:
            self.stages = {
                "input": StageState(status="done", progress=100),
                "preview": StageState(),
                "refine": StageState(),
            }


def safe_filename(latin: str) -> str:
    return "_".join(p.capitalize() for p in latin.split() if p)


def build_preview_prompt(latin: str, hint: str, height_m: float = 0.0) -> str:
    """Build the preview prompt for a plant-only mesh (no pot).

    The hint is expected to describe ONLY the plant (foliage, color, shape) —
    pot descriptions are dropped because pots are generated separately as a
    swappable library on the iOS side. The mesh base must show a clean root
    ball / soil clump so the plant looks natural when dropped into any pot.

    `height_m` is appended to the prompt only as a textual hint for Meshy's
    auto_size feature ("approx 1.2 meters tall"). The actual scaling is done
    by Meshy server-side when `auto_size=True` is set on the API payload.
    """
    parts = [f"a {latin} houseplant"]
    if hint:
        parts.append(hint)
    parts.extend([
        "no pot, no container",
        "exposed root ball at base",
        "compact soil clump under the plant",
        "realistic plant only",
        "symmetric front view",
        "studio lighting",
        "white background",
    ])
    if height_m > 0:
        parts.append(f"approximately {height_m:.2f} meters tall")
    return ", ".join(parts)


def build_pot_prompt(style: str, height_m: float = 0.0) -> str:
    """Build the preview prompt for a pot-only mesh.

    Style is a free-form English description ("terracotta pot, modern ceramic
    white pot, hanging clay pot"). The pot must be empty (no soil, no plant)
    and have a stable flat base so it sits cleanly on the ground in AR.
    """
    parts = [
        style,
        "empty",
        "no plant",
        "no soil",
        "flat stable base",
        "realistic PBR texture",
        "studio lighting",
        "white background",
    ]
    if height_m > 0:
        parts.append(f"approximately {height_m:.2f} meters tall")
    return ", ".join(parts)


def build_texture_prompt(latin: str, hint: str) -> str:
    """Texture refinement prompt. Plant-only — no pot mention so the
    refine step doesn't bake pot materials onto the plant geometry."""
    parts = [f"realistic PBR texture of {latin} plant"]
    if hint:
        parts.append(hint)
    parts.extend([
        "natural plant materials only",
        "visible soil and root ball at base",
    ])
    return ", ".join(parts)


def scan_existing_jobs(output_dir: Path, known_plants: list[dict]) -> list[Job]:
    """Rebuild Job objects from files already present in the output directory.

    Used at server startup to pre-populate the UI with previously generated
    plants. Cross-references with the parsed input.txt (when provided) so the
    common name and hint are restored; falls back to the latin name extracted
    from the filename otherwise.
    """
    by_id = {safe_filename(p["latin"]): p for p in known_plants}
    jobs: list[Job] = []
    seen: set[str] = set()

    def reconstruct(job_id: str) -> Job:
        meta = by_id.get(job_id)
        if meta:
            return make_job(meta["common"], meta["latin"], meta.get("hint", ""))
        # Fallback: filename "Sansevieria_Trifasciata" → latin "sansevieria trifasciata"
        latin = " ".join(part.lower() for part in job_id.split("_") if part)
        return make_job(common=latin.title(), latin=latin, hint="")

    # Full-flow results: identified by the presence of {job_id}.usdz
    for usdz_path in sorted(output_dir.glob("*.usdz")):
        job_id = usdz_path.stem
        if job_id in seen:
            continue
        seen.add(job_id)

        job = reconstruct(job_id)
        job.job_id = job_id

        preview_glb = output_dir / f"{job_id}_preview.glb"
        final_glb = output_dir / f"{job_id}.glb"

        job.stages["preview"].status = "done"
        job.stages["preview"].progress = 100
        if preview_glb.exists():
            job.stages["preview"].glb_file = preview_glb.name

        job.stages["refine"].status = "done"
        job.stages["refine"].progress = 100
        if final_glb.exists():
            job.stages["refine"].glb_file = final_glb.name
            job.final_glb = final_glb.name
        job.stages["refine"].usdz_file = usdz_path.name
        job.final_usdz = usdz_path.name

        jobs.append(job)

    # Preview-only results: {job_id}_preview.glb without a matching usdz
    for preview_path in sorted(output_dir.glob("*_preview.glb")):
        stem = preview_path.stem
        if not stem.endswith("_preview"):
            continue
        job_id = stem[: -len("_preview")]
        if job_id in seen:
            continue
        seen.add(job_id)

        job = reconstruct(job_id)
        job.job_id = job_id
        job.stages["preview"].status = "done"
        job.stages["preview"].progress = 100
        job.stages["preview"].glb_file = preview_path.name
        jobs.append(job)

    return jobs


def make_job(common: str, latin: str, hint: str = "", height_m: float = 0.0) -> Job:
    # Mirror the Meshy website's "Texture" button behavior: it auto-fills the
    # texture prompt with the original preview prompt. We do the same by
    # aliasing texture_prompt to prompt. Override manually if you need to
    # force specific material hints later (call build_texture_prompt).
    prompt = build_preview_prompt(latin, hint, height_m=height_m)
    return Job(
        job_id=safe_filename(latin),
        common=common,
        latin=latin,
        hint=hint,
        prompt=prompt,
        texture_prompt=prompt,
    )


class PipelineRunner:
    def __init__(self, client: MeshyClient, output_dir: Path,
                 on_event: Optional[Callable[["Job"], None]] = None):
        self.client = client
        self.output_dir = output_dir
        self.on_event = on_event or (lambda _job: None)

    def run(self, job: Job, *, preview_only: bool = False) -> None:
        try:
            self._stage_preview(job)
        except Exception:
            return
        if preview_only:
            return
        try:
            self._stage_refine(job)
        except Exception:
            return

    def _stage_preview(self, job: Job) -> None:
        s = job.stages["preview"]
        s.status = "running"
        s.started_at = time.time()
        self.on_event(job)
        try:
            task_id = self.client.create_preview(job.prompt, lowpoly=True)
            s.task_id = task_id
            self.on_event(job)

            def progress_cb(_status, progress, _data):
                s.progress = progress
                self.on_event(job)

            data = self.client.poll(task_id, on_progress=progress_cb)
            urls = data.get("model_urls") or {}
            if urls.get("glb"):
                out = self.output_dir / f"{job.job_id}_preview.glb"
                self.client.download(urls["glb"], out)
                s.glb_file = out.name
            s.status = "done"
            s.progress = 100
            s.finished_at = time.time()
            self.on_event(job)
        except Exception as e:
            s.status = "failed"
            s.error = str(e)
            self.on_event(job)
            raise

    def _stage_refine(self, job: Job) -> None:
        s = job.stages["refine"]
        preview_id = job.stages["preview"].task_id
        if not preview_id:
            s.status = "failed"
            s.error = "no preview_task_id"
            self.on_event(job)
            raise RuntimeError(s.error)

        s.status = "running"
        s.started_at = time.time()
        self.on_event(job)
        try:
            task_id = self.client.create_refine(
                preview_id, texture_prompt=job.texture_prompt, enable_pbr=True)
            s.task_id = task_id
            self.on_event(job)

            def progress_cb(_status, progress, _data):
                s.progress = progress
                self.on_event(job)

            data = self.client.poll(task_id, on_progress=progress_cb)
            urls = data.get("model_urls") or {}
            if urls.get("glb"):
                out = self.output_dir / f"{job.job_id}.glb"
                self.client.download(urls["glb"], out)
                s.glb_file = out.name
                job.final_glb = out.name
            if urls.get("usdz"):
                out = self.output_dir / f"{job.job_id}.usdz"
                self.client.download(urls["usdz"], out)
                # Inject subdivisionScheme=none so iOS RealityKit/ARView doesn't
                # apply Catmull-Clark subdivision to the triangle mesh and
                # break the geometry. See usdz_patch.py for the full rationale.
                patch_usdz_subdivision(out)
                s.usdz_file = out.name
                job.final_usdz = out.name
            s.status = "done"
            s.progress = 100
            s.finished_at = time.time()
            self.on_event(job)
        except Exception as e:
            s.status = "failed"
            s.error = str(e)
            self.on_event(job)
            raise
