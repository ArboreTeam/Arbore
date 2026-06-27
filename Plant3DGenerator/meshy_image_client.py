"""Thin wrapper around the Meshy **Image-to-3D** REST API (v1, single-stage).

Unlike text-to-3D (v2, preview→refine, see meshy_client.py), image-to-3D is a
single call: you submit one image (public URL or base64 data URI) and Meshy
returns a textured model directly. We use it to turn a real botanic.com product
photo into a 3D plant model.

Docs: https://docs.meshy.ai/en/api/image-to-3d
Reuses the exponential-backoff retry helper from meshy_client.
"""
from __future__ import annotations

import base64
import mimetypes
import time
from pathlib import Path
from typing import Callable, Optional

import requests

from meshy_client import _request_with_retry  # shared 429/5xx backoff

BASE_URL = "https://api.meshy.ai/openapi/v1/image-to-3d"


def image_to_data_uri(path: Path) -> str:
    """Encode a local image as a base64 data URI accepted by `image_url`."""
    mime = mimetypes.guess_type(str(path))[0] or "image/png"
    data = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{data}"


class MeshyImageClient:
    def __init__(self, api_key: str):
        if not api_key:
            raise ValueError("api_key is required")
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        })

    def create(self, image: str, *, ai_model: str = "meshy-6",
               should_texture: bool = True, enable_pbr: bool = True,
               texture_prompt: str = "", target_polycount: int = 30000,
               topology: str = "triangle",
               formats: Optional[list] = None) -> str:
        """Create an image-to-3D task. `image` is a public URL or data URI.

        Returns the task id. 30 credits base (+10 if texture_prompt is given).
        """
        payload = {
            "image_url": image,
            "ai_model": ai_model,
            "should_texture": should_texture,
            "enable_pbr": enable_pbr,
            "target_polycount": target_polycount,
            "topology": topology,
            "target_formats": formats or ["glb", "usdz"],
        }
        if texture_prompt:
            payload["texture_prompt"] = texture_prompt
        r = _request_with_retry("POST", BASE_URL, session=self.session,
                                json=payload, timeout=60)
        r.raise_for_status()
        return r.json()["result"]

    def get_task(self, task_id: str) -> dict:
        r = _request_with_retry("GET", f"{BASE_URL}/{task_id}",
                                session=self.session, timeout=30)
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
