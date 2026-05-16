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


def safe_pot_filename(pot_id: str) -> str:
    """File-system safe name for a pot USDZ : `pot_<snake_id>`. Used to
    distinguish pot files from plant files in the shared output/ dir."""
    safe = "_".join(p.lower() for p in pot_id.replace("-", "_").split("_") if p)
    return f"pot_{safe}"


# Habit values supported in input.txt column 5. Each maps to a specific
# block of prompt hints injected by `build_preview_prompt` to bias Meshy
# toward the correct cascade behavior. Default = "upright" when missing
# from input.txt (backward compat).
SUPPORTED_HABITS = {"upright", "trailing", "arching", "bushy"}


def build_preview_prompt(latin: str, hint: str, height_m: float = 0.0,
                         habit: str = "upright") -> str:
    """Build the preview prompt for a plant-only mesh — "soil line" convention.

    The plant is generated with **NO motte / root ball / soil clump** at the
    base. Convention used by professional 3D plant libraries (TurboSquid,
    Sketchfab "potted plant — plant only" assets) : the USDZ contains only
    what's visible ABOVE the soil line (leaves, stems, foliage). The mesh
    is cut clean at the stem base and origin is at Y=0 = soil line.

    Why no root ball : at composition time iOS aligns plant.position.y
    with pot.soilSurfaceY. If the plant carried its own motte, the motte
    would either poke out the sides (motte wider than pot rim) or float
    above the pot's visible soil disc (motte too small). Cutting at the
    soil line lets a single plant mesh combine with any pot of any
    diameter as long as the camera doesn't dive UNDER the rim — which it
    doesn't in AR/catalogue eye-level views.

    `habit` (cf issue #185) drives a habit-specific block to guide Meshy
    on cascade behavior. Trailing / arching plants have foliage that
    drapes BELOW the soil line (Y < 0) outside an imaginary pot rim ;
    upright / bushy plants have all their visible foliage ABOVE Y = 0.
    Without this guidance Meshy can position trailing vines too close to
    the central axis, leading to runtime clipping through the pot wall.

    The hint describes ONLY the plant (foliage, color, habit) — no pot,
    no motte, no soil. `height_m` is injected as a textual hint for
    Meshy `auto_size` server-side.
    """
    parts = [f"a {latin} houseplant"]
    if hint:
        parts.append(hint)
    parts.extend([
        # The "no" stack — repeated phrasings to bias Meshy away from its
        # default "plant comes with soil" training prior.
        "leaves stems and foliage only",
        "cut clean at the base of the stem",
        "no roots visible",
        "no soil, no soil clump, no root ball, no motte",
        "no pot, no container, no base, no plinth",
        "stem emerging from invisible ground plane",
        "ready to be inserted into a separate pot",
    ])
    # Habit-specific cascade guidance (issue #185, solution B).
    habit_norm = habit.lower().strip() if habit else "upright"
    if habit_norm == "trailing":
        parts.extend([
            "long vines that drape outward over an invisible pot rim",
            "cascading foliage falling below the soil line outside the pot",
            "trailing stems hanging vertically beside an imaginary 20 cm rim",
        ])
    elif habit_norm == "arching":
        parts.extend([
            "fronds arching outward then curving downward",
            "foliage extending sideways past an invisible pot rim before falling",
        ])
    elif habit_norm == "bushy":
        parts.extend([
            "dense compact foliage above the soil line",
            "rounded crown of leaves, no trailing parts",
        ])
    else:  # "upright" or unrecognised → safe default
        parts.extend([
            "upright growth strictly above the soil line",
            "no trailing leaves, no foliage below the stem base",
        ])
    parts.extend([
        # Visual quality hints.
        "realistic indoor plant",
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
    """Texture refinement prompt. Soil-line convention — no soil, no pot
    so the refine step doesn't bake those materials onto the plant
    geometry. Mirror of build_preview_prompt's "no" stack."""
    parts = [f"realistic PBR texture of {latin} plant"]
    if hint:
        parts.append(hint)
    parts.extend([
        "natural plant materials only",
        "no soil texture, no pot texture, no terracotta",
        "leaves stems foliage materials only",
    ])
    return ", ".join(parts)


def scan_existing_jobs(output_dir: Path, known_plants: list[dict],
                       known_pots: list[dict] | None = None) -> list[Job]:
    """Rebuild Job objects from files already present in the output directory.

    Used at server startup to pre-populate the UI with previously generated
    assets. Cross-references with parsed input.txt (plants) and pots.txt
    (pots) when provided so the common name + style are restored. Pots are
    identified by their `pot_` filename prefix.
    """
    plants_by_id = {safe_filename(p["latin"]): p for p in known_plants}
    pots_by_id = {safe_pot_filename(p["pot_id"]): p for p in (known_pots or [])}
    jobs: list[Job] = []
    seen: set[str] = set()

    def reconstruct(job_id: str) -> Job:
        # Pot job ? Prefix-based detection — robust as long as no plant
        # latin name starts with "Pot_" (none do in the houseplant catalogue).
        if job_id.startswith("pot_"):
            meta = pots_by_id.get(job_id)
            if meta:
                return make_pot_job(
                    meta["pot_id"], meta["display_name"], meta["style"],
                    top_diameter_cm=meta.get("top_diameter_cm", 0.0),
                    height_cm=meta.get("height_cm", 0.0),
                )
            # Fallback: derive a display name from the suffix.
            short = job_id[len("pot_"):].replace("_", " ").title()
            return make_pot_job(job_id[len("pot_"):], short, short)
        meta = plants_by_id.get(job_id)
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


def make_pot_job(pot_id: str, display_name: str, style: str,
                 top_diameter_cm: float = 0.0, height_cm: float = 0.0) -> Job:
    """Pot-specific make_job. Stores prompt + identity ; the runner doesn't
    care whether it's a plant or a pot (same preview→refine pipeline)."""
    height_m = height_cm / 100.0 if height_cm > 0 else 0.0
    prompt = build_pot_prompt(style, height_m=height_m)
    if top_diameter_cm > 0:
        prompt += f", approximately {top_diameter_cm / 100.0:.2f} meters wide at the top"
    return Job(
        job_id=safe_pot_filename(pot_id),
        common=display_name,
        latin=pot_id,                  # reuse `latin` slot to carry the canonical id
        hint=style,
        prompt=prompt,
        texture_prompt=prompt,
    )


def make_job(common: str, latin: str, hint: str = "", height_m: float = 0.0,
             habit: str = "upright") -> Job:
    # Mirror the Meshy website's "Texture" button behavior: it auto-fills the
    # texture prompt with the original preview prompt. We do the same by
    # aliasing texture_prompt to prompt. Override manually if you need to
    # force specific material hints later (call build_texture_prompt).
    prompt = build_preview_prompt(latin, hint, height_m=height_m, habit=habit)
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
