#!/usr/bin/env bash
# Build a backup .zip of ALL botanic plant 3D assets in the deploy architecture:
#   models/            light USDZ (served by default — catalogue + AR placement)
#   models/heavy/      heavy USDZ (real specimen — LOD swap during AR viewing)
#   models/thumbnails/ PNG catalogue thumbnails
# Files are named by plant (human-readable). Uses hardlinks to avoid doubling
# disk usage while staging. Originals untouched.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
MANIFEST="$REPO/BotanicScraper/data/manifest.json"
THUMB_MAP="$HERE/_thumb_map.json"
STAGE="${1:-$HERE/arbore-3d-models}"
ZIP_OUT="${2:-$HERE/arbore-3d-models.zip}"

rm -rf "$STAGE" "$ZIP_OUT"
mkdir -p "$STAGE/models/heavy" "$STAGE/models/thumbnails"

# stage light + heavy by model filename (only the included manifest plants)
python3 - "$MANIFEST" "$HERE" "$STAGE" "$THUMB_MAP" <<'PY'
import json, os, sys, shutil
manifest, gen_dir, stage, thumb_map = sys.argv[1:5]
plants = [p for p in json.load(open(manifest))["plants"] if p["include"]]
opti = os.path.join(gen_dir, "opti_output")
heavy = os.path.join(gen_dir, "output")
tmap = {m["model"]: m["id"] for m in json.load(open(thumb_map))}
thumb_src = os.path.join(os.path.dirname(gen_dir), "ArboreBackend", "models", "thumbnails")

def link(src, dst):
    if os.path.exists(src):
        try: os.link(src, dst)        # hardlink (same FS, no extra space)
        except OSError: shutil.copy2(src, dst)
        return True
    return False

light_ok = heavy_ok = thumb_ok = miss = 0
seen = set()
for p in plants:
    mf = p["modelFilename"]
    if mf in seen: continue
    seen.add(mf)
    if link(os.path.join(opti, mf), os.path.join(stage, "models", mf)): light_ok += 1
    else: miss += 1; print("  ⚠️ no light:", mf)
    if link(os.path.join(heavy, mf), os.path.join(stage, "models", "heavy", mf)): heavy_ok += 1
    # thumbnail: stored on backend as <plantId>.png → copy as <ModelName>.png
    pid = tmap.get(mf)
    if pid:
        png = os.path.join(thumb_src, pid + ".png")
        if link(png, os.path.join(stage, "models", "thumbnails", mf[:-5] + ".png")): thumb_ok += 1

print(f"botanic staged — light:{light_ok} heavy:{heavy_ok} thumbnails:{thumb_ok} missing-light:{miss}")

# legacy (unique prod models not covered by botanic): light=_legacy/light,
# heavy=_legacy/heavy (original), thumbnails=_legacy/thumbnails (by model name)
leg_dir = os.path.join(gen_dir, "_legacy")
ll = lh = lt = 0
import glob as _glob
for lf in sorted(_glob.glob(os.path.join(leg_dir, "light", "*.usdz"))):
    name = os.path.basename(lf)
    stem = name[:-5]
    if link(lf, os.path.join(stage, "models", name)): ll += 1
    if link(os.path.join(leg_dir, "heavy", name), os.path.join(stage, "models", "heavy", name)): lh += 1
    if link(os.path.join(leg_dir, "thumbnails", stem + ".png"), os.path.join(stage, "models", "thumbnails", stem + ".png")): lt += 1
print(f"legacy staged  — light:{ll} heavy:{lh} thumbnails:{lt}")
print(f"TOTAL catalogue: {light_ok + ll} plants (botanic {light_ok} + legacy {ll})")
PY

# README + id mapping for the team
cp "$THUMB_MAP" "$STAGE/plantId_to_model.json" 2>/dev/null || true
cat > "$STAGE/README.txt" <<EOF
Arbore — botanic plant 3D assets (backup)
=========================================
Deploy architecture (rsync to VPS ArboreBackend/models/):
  models/             LIGHT usdz  — served by default (catalogue + initial AR placement)
  models/heavy/       HEAVY usdz  — real high-detail specimen, loaded in background during
                                    AR viewing then swapped in (LOD), then light is freed
  models/thumbnails/  PNG         — catalogue card thumbnails

Notes:
- Files named by plant. The backend serves thumbnails as <plantId>.png; see
  plantId_to_model.json for the model->id mapping (ids are from arbore_test).
- LIGHT = decimated (gltf-transform) for most; text-to-3D lowpoly for the few
  feathery plants the decimator couldn't shrink. HEAVY = original Meshy image-to-3D.
Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "=== sizes ==="
du -sh "$STAGE/models" "$STAGE/models/heavy" "$STAGE/models/thumbnails"
echo "=== zipping (this is large) ==="
( cd "$STAGE/.." && zip -r -q "$ZIP_OUT" "$(basename "$STAGE")" )
echo "✅ $ZIP_OUT  ($(du -sh "$ZIP_OUT" | awk '{print $1}'))"
