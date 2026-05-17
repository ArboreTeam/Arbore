#!/usr/bin/env bash
# Downloads Apple's pre-converted Depth Anything V2 Small (CoreML) into the
# iOS app's bundle resources folder.
#
# The model is ~50MB (.mlpackage), gitignored — we don't track it in the
# repo. Every fresh checkout / CI runner must run this script before
# building the ML-enabled targets.
#
# Source: https://huggingface.co/apple/coreml-depth-anything-v2-small
# License: Apple Sample Code License (re-distribution OK in apps).
#
# Usage:
#   ./scripts/fetch-depth-model.sh
#
# Exits 0 if model already present (idempotent).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$REPO_ROOT/ArboreUi/ArboreUi/ARGarden/DepthMesh/Models"
PKG_NAME="DepthAnythingV2SmallF16.mlpackage"
HF_REPO="apple/coreml-depth-anything-v2-small"

mkdir -p "$DEST_DIR"

if [ -d "$DEST_DIR/$PKG_NAME" ]; then
  echo "✓ $PKG_NAME already present at $DEST_DIR — skipping download."
  exit 0
fi

# Prefer huggingface-cli if installed, else fall back to a curl loop
# over the HF API.
if command -v huggingface-cli >/dev/null 2>&1; then
  echo "→ Downloading $PKG_NAME via huggingface-cli…"
  huggingface-cli download \
    --local-dir "$DEST_DIR" --local-dir-use-symlinks False \
    "$HF_REPO" \
    --include "$PKG_NAME/*"
else
  echo "→ huggingface-cli not found, falling back to curl + HF API."
  echo "  (Install with: pip install -U 'huggingface_hub[cli]')"

  API_BASE="https://huggingface.co/api/models/$HF_REPO/tree/main/$PKG_NAME"
  RAW_BASE="https://huggingface.co/$HF_REPO/resolve/main/$PKG_NAME"

  # Walk the tree recursively; HF returns JSON, we curl + parse with python.
  python3 - "$API_BASE" "$RAW_BASE" "$DEST_DIR/$PKG_NAME" <<'PY'
import json, os, sys, urllib.request

api_base, raw_base, dest_root = sys.argv[1], sys.argv[2], sys.argv[3]

def walk(api_url, raw_url, dest):
    with urllib.request.urlopen(api_url) as r:
        tree = json.load(r)
    for entry in tree:
        path = entry["path"].split("/", 1)[-1]  # strip "DepthAnythingV2SmallF16.mlpackage/"
        if entry["type"] == "directory":
            os.makedirs(os.path.join(dest, path), exist_ok=True)
            walk(api_url + "/" + path, raw_url + "/" + path, dest)
        else:
            target = os.path.join(dest, path)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            if os.path.exists(target):
                continue
            print(f"  {path}")
            with urllib.request.urlopen(raw_url + "/" + path) as r, open(target, "wb") as f:
                f.write(r.read())

os.makedirs(dest_root, exist_ok=True)
walk(api_base, raw_base, dest_root)
PY
fi

echo
echo "✓ Model installed at $DEST_DIR/$PKG_NAME"
echo
echo "Next steps (one-time, Xcode):"
echo "  1. Open ArboreUi.xcodeproj"
echo "  2. Drag $PKG_NAME into the ArboreUi target → Copy items if needed"
echo "  3. Verify it appears under 'Copy Bundle Resources' build phase"
