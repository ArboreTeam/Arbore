#!/usr/bin/env bash
# Downloads Apple-converted CoreML models needed by the Scene Understanding
# pipeline (issue #187 / #186 Phase 3):
#   - DepthAnythingV2SmallF16.mlpackage    (~47 MB, monocular depth)
#   - DETRResnet50SemanticSegmentationF16.mlpackage (~86 MB, 133 COCO classes)
#
# Models live in ArboreUi/ArboreUi/ARGarden/SceneUnderstanding/Models/ and are
# gitignored (*.mlpackage/). Idempotent : skips files already present, so
# safe to wire into an Xcode Run Script build phase as a no-op on repeat
# builds.
#
# Sources :
#   https://huggingface.co/apple/coreml-depth-anything-v2-small
#   https://huggingface.co/apple/coreml-detr-semantic-segmentation
# License : Apple Sample Code (re-distribution OK in apps).
#
# Usage :
#   ./scripts/fetch-ml-models.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_ROOT="$REPO_ROOT/ArboreUi/ArboreUi/ARGarden/SceneUnderstanding/Models"
mkdir -p "$DEST_ROOT"

fetch_mlpackage () {
  local hf_repo="$1"
  local pkg_name="$2"
  local dest="$DEST_ROOT/$pkg_name"

  if [ -d "$dest" ] && [ -f "$dest/Manifest.json" ] && [ -f "$dest/Data/com.apple.CoreML/weights/weight.bin" ]; then
    echo "✓ $pkg_name already present — skipping."
    return 0
  fi

  echo "→ Downloading $pkg_name from $hf_repo …"

  if command -v huggingface-cli >/dev/null 2>&1; then
    huggingface-cli download \
      --local-dir "$DEST_ROOT" --local-dir-use-symlinks False \
      "$hf_repo" \
      --include "$pkg_name/*" >/dev/null
  else
    # Fallback: curl the 3 well-known files directly (Apple's converted
    # .mlpackage layout is stable since 2024).
    local base="https://huggingface.co/$hf_repo/resolve/main/$pkg_name"
    mkdir -p "$dest/Data/com.apple.CoreML/weights"
    curl -fsSL "$base/Manifest.json" -o "$dest/Manifest.json"
    curl -fsSL "$base/Data/com.apple.CoreML/model.mlmodel" -o "$dest/Data/com.apple.CoreML/model.mlmodel"
    echo "  fetching weight.bin (the big one)…"
    curl -fL "$base/Data/com.apple.CoreML/weights/weight.bin" -o "$dest/Data/com.apple.CoreML/weights/weight.bin" --progress-bar
  fi

  echo "  done : $(du -sh "$dest" | awk '{print $1}')"
}

fetch_mlpackage "apple/coreml-depth-anything-v2-small" "DepthAnythingV2SmallF16.mlpackage"
fetch_mlpackage "apple/coreml-detr-semantic-segmentation" "DETRResnet50SemanticSegmentationF16.mlpackage"

echo
echo "✓ All models installed at $DEST_ROOT"
echo "  Xcode 16 PBXFileSystemSynchronizedRootGroup auto-includes .mlpackage"
echo "  bundles. Next build will compile them to .mlmodelc into the IPA."
