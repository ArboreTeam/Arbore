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


def build_preview_prompt(latin: str, hint: str) -> str:
    parts = [f"a potted {latin}"]
    if hint:
        parts.append(hint)
    parts.extend([
        "realistic houseplant",
        "symmetric front view",
        "studio lighting",
        "white background",
        "full plant visible including pot",
    ])
    return ", ".join(parts)


def build_texture_prompt(latin: str, hint: str) -> str:
    parts = [f"realistic PBR texture of {latin}"]
    if hint:
        parts.append(hint)
    parts.append("natural terracotta pot")
    return ", ".join(parts)


def make_job(common: str, latin: str, hint: str = "") -> Job:
    # Mirror the Meshy website's "Texture" button behavior: it auto-fills the
    # texture prompt with the original preview prompt. We do the same by
    # aliasing texture_prompt to prompt. Override manually if you need to
    # force specific material hints later (call build_texture_prompt).
    prompt = build_preview_prompt(latin, hint)
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
