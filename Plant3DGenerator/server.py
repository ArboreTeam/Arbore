"""Local web UI for Plant3DGenerator — live Meshy pipeline visualization."""
from __future__ import annotations

import asyncio
import json
import os
import threading
import webbrowser
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from dataclasses import asdict
from pathlib import Path
from typing import Optional

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from meshy_client import MeshyClient
from pipeline import Job, PipelineRunner, make_job, make_pot_job, scan_existing_jobs

ROOT = Path(__file__).parent
OUTPUT_DIR = ROOT / "output"
OUTPUT_DIR.mkdir(exist_ok=True)
STATIC_DIR = ROOT / "static"

load_dotenv(ROOT / ".env")
API_KEY = os.getenv("MESHY_API_KEY")
if not API_KEY:
    raise SystemExit("❌ MESHY_API_KEY not set — copy .env.example to .env and fill it in")

_client = MeshyClient(API_KEY)

# Cap concurrent meshy pipelines to stay safely under the Pro tier's 10
# concurrent queue tasks limit. Each running job has at most 1 active meshy
# task (preview xor refine) at any time, so 5 workers ≤ 5 concurrent tasks.
_executor = ThreadPoolExecutor(max_workers=5, thread_name_prefix="plant3d")

_jobs: dict[str, Job] = {}
_subscribers: list[asyncio.Queue] = []
_lock = threading.Lock()
_loop: Optional[asyncio.AbstractEventLoop] = None


def _job_to_dict(job: Job) -> dict:
    return {
        "job_id": job.job_id,
        "common": job.common,
        "latin": job.latin,
        "hint": job.hint,
        "prompt": job.prompt,
        "texture_prompt": job.texture_prompt,
        "stages": {k: asdict(v) for k, v in job.stages.items()},
        "final_glb": job.final_glb,
        "final_usdz": job.final_usdz,
    }


def _emit(job: Job) -> None:
    with _lock:
        payload = json.dumps(_job_to_dict(job))
    if _loop is None:
        return
    for q in list(_subscribers):
        def _push(queue=q, msg=payload):
            try:
                queue.put_nowait(msg)
            except asyncio.QueueFull:
                pass
        _loop.call_soon_threadsafe(_push)


_runner = PipelineRunner(_client, OUTPUT_DIR, on_event=_emit)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global _loop
    _loop = asyncio.get_running_loop()

    existing = scan_existing_jobs(OUTPUT_DIR, _read_input_plants(), _read_input_pots())
    with _lock:
        for job in existing:
            _jobs[job.job_id] = job
    if existing:
        print(f"📦 Loaded {len(existing)} existing job(s) from output/")

    try:
        yield
    finally:
        _loop = None


app = FastAPI(title="Plant3DGenerator", lifespan=lifespan)


class StartJobReq(BaseModel):
    common: str
    latin: str
    hint: str = ""
    height_m: float = 0.0
    habit: str = "upright"
    preview_only: bool = False


class StartPotJobReq(BaseModel):
    pot_id: str
    display_name: str
    style: str
    top_diameter_cm: float = 0.0
    height_cm: float = 0.0
    preview_only: bool = False


@app.get("/")
def index():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/state")
def get_state():
    with _lock:
        return JSONResponse([_job_to_dict(j) for j in _jobs.values()])


def _read_input_plants() -> list[dict]:
    """See generate.parse_input for format ; kept duplicated here to avoid
    a CLI ↔ server dependency cycle. Columns 4 (height_m), 5 (habit) and
    6 (default_pot_id) sont remontées dans /api/input pour le composer."""
    plants: list[dict] = []
    path = ROOT / "input.txt"
    if not path.exists():
        return plants
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
            default_pot_id = parts[5] if len(parts) >= 6 and parts[5] else ""
            plants.append({
                "common": parts[0],
                "latin": parts[1],
                "hint": parts[2] if len(parts) >= 3 else "",
                "height_m": height_m,
                "habit": habit,
                "default_pot_id": default_pot_id,
            })
    return plants


@app.get("/api/input")
def get_input():
    return _read_input_plants()


def _read_input_pots() -> list[dict]:
    """Parse pots.txt — one pot per non-comment line.

    Format: pot_id | Display Name | style | top_diameter_cm | height_cm
    """
    pots: list[dict] = []
    path = ROOT / "pots.txt"
    if not path.exists():
        return pots
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) < 3:
                continue
            top_d = 0.0
            height = 0.0
            if len(parts) >= 4 and parts[3]:
                try:
                    top_d = float(parts[3])
                except ValueError:
                    top_d = 0.0
            if len(parts) >= 5 and parts[4]:
                try:
                    height = float(parts[4])
                except ValueError:
                    height = 0.0
            pots.append({
                "pot_id": parts[0],
                "display_name": parts[1],
                "style": parts[2],
                "top_diameter_cm": top_d,
                "height_cm": height,
            })
    return pots


@app.get("/api/pots")
def get_pots():
    return _read_input_pots()


def _enqueue_job(job: Job, preview_only: bool) -> None:
    _executor.submit(_runner.run, job, preview_only=preview_only)


@app.post("/api/generate")
def start_job(req: StartJobReq):
    job = make_job(req.common, req.latin, req.hint,
                   height_m=req.height_m, habit=req.habit)
    with _lock:
        existing = _jobs.get(job.job_id)
        if existing and existing.stages["preview"].status == "running":
            raise HTTPException(409, "already running")
        _jobs[job.job_id] = job
    _emit(job)
    _enqueue_job(job, req.preview_only)
    return {"job_id": job.job_id}


@app.post("/api/generate-pot")
def start_pot_job(req: StartPotJobReq):
    job = make_pot_job(req.pot_id, req.display_name, req.style,
                       top_diameter_cm=req.top_diameter_cm,
                       height_cm=req.height_cm)
    with _lock:
        existing = _jobs.get(job.job_id)
        if existing and existing.stages["preview"].status == "running":
            raise HTTPException(409, "already running")
        _jobs[job.job_id] = job
    _emit(job)
    _enqueue_job(job, req.preview_only)
    return {"job_id": job.job_id}


@app.post("/api/generate-all")
def start_batch():
    """Queue every plant from input.txt that doesn't already have a USDZ in
    output/. Returns the count enqueued and skipped. Submissions are throttled
    by the executor's 5-worker cap so we never exceed the meshy concurrent
    task limit."""
    plants = _read_input_plants()
    enqueued: list[str] = []
    skipped_done: list[str] = []
    skipped_running: list[str] = []

    with _lock:
        for p in plants:
            job = make_job(p["common"], p["latin"], p.get("hint", ""),
                           height_m=p.get("height_m", 0.0),
                           habit=p.get("habit", "upright"))
            existing_usdz = OUTPUT_DIR / f"{job.job_id}.usdz"
            if existing_usdz.exists():
                skipped_done.append(job.job_id)
                continue
            existing_job = _jobs.get(job.job_id)
            if existing_job and existing_job.stages["preview"].status == "running":
                skipped_running.append(job.job_id)
                continue
            _jobs[job.job_id] = job
            enqueued.append(job.job_id)

    # Emit + submit outside the lock to avoid holding it during I/O
    for job_id in enqueued:
        job = _jobs[job_id]
        _emit(job)
        _enqueue_job(job, preview_only=False)

    return {
        "enqueued": len(enqueued),
        "skipped_done": len(skipped_done),
        "skipped_running": len(skipped_running),
        "total": len(plants),
    }


@app.get("/api/stream")
async def stream():
    q: asyncio.Queue = asyncio.Queue(maxsize=200)
    _subscribers.append(q)

    async def gen():
        try:
            with _lock:
                initial = [_job_to_dict(j) for j in _jobs.values()]
            yield f"event: snapshot\ndata: {json.dumps(initial)}\n\n"
            while True:
                try:
                    msg = await asyncio.wait_for(q.get(), timeout=15)
                    yield f"event: update\ndata: {msg}\n\n"
                except asyncio.TimeoutError:
                    yield ": ping\n\n"
        except asyncio.CancelledError:
            raise
        finally:
            if q in _subscribers:
                _subscribers.remove(q)

    return StreamingResponse(gen(), media_type="text/event-stream")


app.mount("/output", StaticFiles(directory=OUTPUT_DIR), name="output")
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


def main():
    port = int(os.getenv("PORT", "5555"))
    url = f"http://localhost:{port}"
    print(f"🌱 Plant3DGenerator UI → {url}")
    threading.Timer(1.0, lambda: webbrowser.open(url)).start()
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning")


if __name__ == "__main__":
    main()
