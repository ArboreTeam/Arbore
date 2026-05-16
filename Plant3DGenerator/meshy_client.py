"""Thin wrapper around the Meshy text-to-3D REST API."""
from __future__ import annotations

import time
from pathlib import Path
from typing import Callable, Optional

import requests

BASE_URL = "https://api.meshy.ai/openapi/v2/text-to-3d"

# Meshy Pro-tier rate limits (per docs):
#   - 20 requests/second
#   - 10 concurrent queue tasks
# 429 is returned as RateLimitExceeded (req/s) or NoMoreConcurrentTasks (queue).
_MAX_RETRIES = 6
_BASE_BACKOFF = 4.0  # seconds; doubles on each retry


def _request_with_retry(method: str, url: str, *, session: requests.Session,
                        **kwargs) -> requests.Response:
    """Wrap a request with exponential backoff on 429 and transient 5xx."""
    for attempt in range(_MAX_RETRIES):
        resp = session.request(method, url, **kwargs)
        if resp.status_code == 429 or 500 <= resp.status_code < 600:
            retry_after = resp.headers.get("Retry-After")
            if retry_after and retry_after.isdigit():
                wait = float(retry_after)
            else:
                wait = _BASE_BACKOFF * (2 ** attempt)
            print(f"⏳ meshy {resp.status_code} on {method} {url.split('/')[-1]}, "
                  f"retry {attempt + 1}/{_MAX_RETRIES} in {wait:.0f}s")
            time.sleep(wait)
            continue
        return resp
    return resp  # last response (failure)


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
                       formats: Optional[list] = None,
                       auto_size: bool = True,
                       origin_at: str = "bottom",
                       negative_prompt: str = "") -> str:
        """Create a Meshy preview task.

        `auto_size=True` lets Meshy resize the mesh to a realistic height
        estimated from the prompt (avoids the need for a separate Python
        post-process to scale plants to species-level dimensions).

        `origin_at="bottom"` parks the mesh origin at the base of the bbox
        so iOS can drop the USDZ at the raycast hit point without computing
        a pivot offset for the model's lowest vertex.

        `negative_prompt` (Meshy v2 native) suppresses concepts that should
        NOT appear in the mesh. Bias-breaking : Meshy's training corpus
        strongly associates "pot" with "plant inside", so saying "no plant"
        in the positive prompt is often ignored — negative prompt is far
        more effective.
        """
        payload = {
            "mode": "preview",
            "prompt": prompt,
            "model_type": "lowpoly" if lowpoly else "standard",
            "target_formats": formats or ["glb", "usdz"],
            "auto_size": auto_size,
            "origin_at": origin_at,
        }
        if negative_prompt:
            payload["negative_prompt"] = negative_prompt
        r = _request_with_retry("POST", BASE_URL, session=self.session,
                                json=payload, timeout=30)
        r.raise_for_status()
        return r.json()["result"]

    def create_refine(self, preview_id: str, *, texture_prompt: str = "",
                      enable_pbr: bool = True, remove_lighting: bool = True,
                      ai_model: str = "meshy-6",
                      negative_prompt: str = "") -> str:
        payload = {
            "mode": "refine",
            "preview_task_id": preview_id,
            "ai_model": ai_model,
            "enable_pbr": enable_pbr,
            "remove_lighting": remove_lighting,
        }
        if texture_prompt:
            payload["texture_prompt"] = texture_prompt
        if negative_prompt:
            payload["negative_prompt"] = negative_prompt
        r = _request_with_retry("POST", BASE_URL, session=self.session,
                                json=payload, timeout=30)
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
