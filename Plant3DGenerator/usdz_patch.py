"""Post-process meshy-generated USDZ files for iOS ARView compatibility.

Meshy never sets the `subdivisionScheme` attribute on its meshes. Per the USD
spec, the default when the attribute is absent is `catmullClark`, which iOS
RealityKit honors strictly inside an ARView session — it tries to apply
Catmull-Clark subdivision to triangle meshes and produces broken/missing
faces (visible "holes" in the model). macOS Quick Look and the Xcode preview
short-circuit this for performance and render fine, masking the problem.

The fix Apple recommends is to explicitly declare `subdivisionScheme = "none"`
on every UsdGeomMesh. This module:

  1. Extracts the USDZ archive
  2. Converts every .usdc to text via `usdcat`
  3. Injects `uniform token subdivisionScheme = "none"` into every mesh block
     that doesn't already declare it
  4. Converts back to .usdc
  5. Repackages as an ARKit-compliant USDZ via `usdzip --arkitAsset`

Requires Apple's `usdcat` and `usdzip` (shipped with Xcode and macOS). Fails
gracefully (returns False, leaves the file untouched) if the tools are
missing or any step errors out.
"""
from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

# `def Mesh "name"\n{\n` — captures everything up to and including the opening brace
# so we can re-emit it followed by the subdivisionScheme declaration.
_MESH_HEADER_RE = re.compile(r'(def Mesh "[^"]+"\s*\n\s*\{\s*\n)')


def _inject_subdivision_none(usda_text: str) -> tuple[str, int]:
    if "subdivisionScheme" in usda_text:
        # Already patched (or future meshy version started declaring it).
        return usda_text, 0

    count = 0

    def replace(match: re.Match) -> str:
        nonlocal count
        count += 1
        return match.group(1) + '    uniform token subdivisionScheme = "none"\n'

    return _MESH_HEADER_RE.sub(replace, usda_text), count


def patch_usdz_subdivision(usdz_path: Path) -> bool:
    """Patch a USDZ in place. Returns True on successful patch, False otherwise."""
    usdcat = shutil.which("usdcat")
    usdzip = shutil.which("usdzip")
    if not usdcat or not usdzip:
        print(f"⚠️  usdcat/usdzip not found, skipping subdivision patch on {usdz_path.name}")
        return False

    if not usdz_path.exists():
        return False

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        try:
            with zipfile.ZipFile(usdz_path) as zf:
                zf.extractall(work)
        except zipfile.BadZipFile:
            print(f"⚠️  {usdz_path.name} is not a valid zip, skipping patch")
            return False

        # USDZ entry files can be .usdc (binary) or .usda (text).
        usd_files = sorted(list(work.glob("*.usdc")) + list(work.glob("*.usda")))
        if not usd_files:
            print(f"⚠️  no usd files inside {usdz_path.name}, skipping patch")
            return False

        total_meshes_patched = 0
        for usd_file in usd_files:
            usda_text_path = work / (usd_file.stem + ".patched.usda")
            try:
                subprocess.run(
                    [usdcat, str(usd_file), "-o", str(usda_text_path)],
                    check=True, capture_output=True, timeout=60,
                )
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                err = e.stderr.decode() if hasattr(e, "stderr") and e.stderr else str(e)
                print(f"⚠️  usdcat failed on {usd_file.name}: {err}")
                return False

            content = usda_text_path.read_text()
            new_content, patched = _inject_subdivision_none(content)
            if patched == 0:
                # Nothing to patch (already done or no meshes).
                continue

            usda_text_path.write_text(new_content)
            try:
                subprocess.run(
                    [usdcat, str(usda_text_path), "-o", str(usd_file)],
                    check=True, capture_output=True, timeout=60,
                )
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                err = e.stderr.decode() if hasattr(e, "stderr") and e.stderr else str(e)
                print(f"⚠️  usdcat (write back) failed on {usd_file.name}: {err}")
                return False

            usda_text_path.unlink(missing_ok=True)
            total_meshes_patched += patched

        if total_meshes_patched == 0:
            return False

        # Repackage as an ARKit-compliant USDZ. We pass the first usd file as
        # the root layer; usdzip resolves dependencies (textures) from the
        # working directory automatically.
        root_layer = usd_files[0].name
        out_tmp = work / "patched.usdz"
        try:
            subprocess.run(
                [usdzip, "--arkitAsset", root_layer, str(out_tmp)],
                check=True, capture_output=True, cwd=work, timeout=120,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            err = e.stderr.decode() if hasattr(e, "stderr") and e.stderr else str(e)
            print(f"⚠️  usdzip failed on {usdz_path.name}: {err}")
            return False

        if not out_tmp.exists():
            print(f"⚠️  usdzip produced no output for {usdz_path.name}")
            return False

        # Atomic-ish replace.
        shutil.move(str(out_tmp), str(usdz_path))
        print(f"🔧 patched {usdz_path.name}: {total_meshes_patched} mesh(es) "
              f"now declare subdivisionScheme=none")
        return True
