"""Local web UI for Plant3DGenerator — live Meshy pipeline visualization."""
from __future__ import annotations

import asyncio
import json
import os
import threading
import webbrowser
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
from pipeline import Job, PipelineRunner, make_job

ROOT = Path(__file__).parent
OUTPUT_DIR = ROOT / "output"
OUTPUT_DIR.mkdir(exist_ok=True)
STATIC_DIR = ROOT / "static"

load_dotenv(ROOT / ".env")
API_KEY = os.getenv("MESHY_API_KEY")
if not API_KEY:
    raise SystemExit("❌ MESHY_API_KEY not set — copy .env.example to .env and fill it in")

_client = MeshyClient(API_KEY)

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
    try:
        yield
    finally:
        _loop = None


app = FastAPI(title="Plant3DGenerator", lifespan=lifespan)


class StartJobReq(BaseModel):
    common: str
    latin: str
    hint: str = ""
    preview_only: bool = False


@app.get("/")
def index():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/state")
def get_state():
    with _lock:
        return JSONResponse([_job_to_dict(j) for j in _jobs.values()])


@app.get("/api/input")
def get_input():
    plants = []
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
            plants.append({
                "common": parts[0],
                "latin": parts[1],
                "hint": parts[2] if len(parts) >= 3 else "",
            })
    return plants


@app.post("/api/generate")
def start_job(req: StartJobReq):
    job = make_job(req.common, req.latin, req.hint)
    with _lock:
        existing = _jobs.get(job.job_id)
        if existing and existing.stages["preview"].status == "running":
            raise HTTPException(409, "already running")
        _jobs[job.job_id] = job
    _emit(job)
    threading.Thread(
        target=_runner.run, args=(job,),
        kwargs={"preview_only": req.preview_only}, daemon=True,
    ).start()
    return {"job_id": job.job_id}


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
