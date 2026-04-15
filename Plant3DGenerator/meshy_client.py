"""Thin wrapper around the Meshy text-to-3D REST API."""
from __future__ import annotations

import time
from pathlib import Path
from typing import Callable, Optional

import requests

BASE_URL = "https://api.meshy.ai/openapi/v2/text-to-3d"


class MeshyClient:
    def __init__(self, api_key: str):
        if not api_key:
            raise ValueError("api_key is required")
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        })

    def create_preview(self, prompt: str, *, lowpoly: bool = True,
                       formats: Optional[list] = None) -> str:
        payload = {
            "mode": "preview",
            "prompt": prompt,
            "model_type": "lowpoly" if lowpoly else "standard",
            "target_formats": formats or ["glb", "usdz"],
        }
        r = self.session.post(BASE_URL, json=payload, timeout=30)
        r.raise_for_status()
        return r.json()["result"]

    def create_refine(self, preview_id: str, *, texture_prompt: str = "",
                      enable_pbr: bool = True, remove_lighting: bool = True,
                      ai_model: str = "meshy-6") -> str:
        payload = {
            "mode": "refine",
            "preview_task_id": preview_id,
            "ai_model": ai_model,
            "enable_pbr": enable_pbr,
            "remove_lighting": remove_lighting,
        }
        if texture_prompt:
            payload["texture_prompt"] = texture_prompt
        r = self.session.post(BASE_URL, json=payload, timeout=30)
        r.raise_for_status()
        return r.json()["result"]

    def get_task(self, task_id: str) -> dict:
        r = self.session.get(f"{BASE_URL}/{task_id}", timeout=30)
        r.raise_for_status()
        return r.json()

    def poll(self, task_id: str, *, interval: int = 5, timeout: int = 900,
             on_progress: Optional[Callable[[str, int, dict], None]] = None) -> dict:
        start = time.time()
        last = -1
        while True:
            if time.time() - start > timeout:
                raise TimeoutError(f"task {task_id} timed out after {timeout}s")
            data = self.get_task(task_id)
            status = data.get("status")
            progress = data.get("progress", 0)
            if on_progress and progress != last:
                on_progress(status, progress, data)
                last = progress
            if status == "SUCCEEDED":
                return data
            if status in ("FAILED", "CANCELED", "EXPIRED"):
                err = data.get("task_error") or {"message": "unknown"}
                raise RuntimeError(f"task {task_id} {status}: {err}")
            time.sleep(interval)

    @staticmethod
    def download(url: str, out_path: Path) -> int:
        r = requests.get(url, timeout=180)
        r.raise_for_status()
        out_path.write_bytes(r.content)
        return len(r.content)
