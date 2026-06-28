# Models Directory

3D plant assets (USDZ) and catalog thumbnails served by the backend. These
files are **large and gitignored** — they are deployed to the VPS out-of-band
(rsync), not committed (see [Git](#git)).

## Layout (LOD)

| Path | Content | Served by |
|---|---|---|
| `models/<Name>.usdz` | **LIGHT** model — optimized, served by default | `GET /models/:filename` |
| `models/heavy/<Name>.usdz` | **HEAVY** model — high-detail variant (same filename) | `GET /models/:filename?lod=heavy` |
| `models/thumbnails/<plantId>.png` | Catalog thumbnail (PNG) | `GET /models/thumbnails/:filename` (public) |

The iOS app places the LIGHT model instantly, then cross-fade-swaps the HEAVY
one in when the adaptive LOD policy allows (`Plant.hasHeavy`). See
[`docs/fr/3d-lod-architecture.md`](../../docs/fr/3d-lod-architecture.md).

## ⚠️ SceneKit material requirement (must read before adding models)

The iOS AR view loads models with **SceneKit** (`SCNScene(url:)`). SceneKit's
USD importer **does not follow** a connected texture file input:

```
# ❌ renders GREY in AR — SceneKit won't resolve the connection
asset inputs:file.connect = </…/Material0.inputs:baseColorTexture>

# ✅ binds correctly — direct asset path on the UsdUVTexture
asset inputs:file = @0/baseColor_1.jpg@
```

A glTF → USD round-trip (the mesh/texture optimizer) produces the connected
form, which is why such plants showed colored thumbnails (RealityKit / Hydra
follow connections) but grey AR models. Fixed in **issue #292**.

- **New models** are handled automatically: `Plant3DGenerator/optimize_models.py`
  rebinds textures to the direct form right after the glTF → USD step.
- **Already-built `.usdz`** can be repaired with:
  - `Plant3DGenerator/fix_scenekit_materials.py` (needs `usdcat`/`usdzip`, e.g. macOS/Xcode), or
  - `Plant3DGenerator/fix_scenekit_materials_pxr.py` (`pip install usd-core`, no CLI — runs anywhere, in place):
    ```bash
    python3 fix_scenekit_materials_pxr.py --inplace --dir <models_dir> --backup <backup_dir>
    ```

## API endpoint

```
GET /models/:filename            # light (default)
GET /models/:filename?lod=heavy  # high-detail variant from models/heavy/
```

**Requirements:** valid `X-API-Key` header **and** Firebase `Authorization: Bearer`
token (thumbnails under `GET /models/thumbnails/:filename` are public).

```bash
curl -H "X-API-Key: YOUR_API_KEY" \
     -H "Authorization: Bearer YOUR_FIREBASE_TOKEN" \
     "http://localhost:8080/models/Monstera_Deliciosa.usdz"
```

## Adding new models

1. Generate/optimize the `.usdz` (see `Plant3DGenerator/`) — the optimizer
   emits SceneKit-correct materials.
2. Place the LIGHT `.usdz` here and the HEAVY one in `models/heavy/` (same filename).
3. Set the plant's `modelURL` (and `hasHeavy` if a heavy variant exists) in MongoDB.
4. Deploy the files to the VPS (rsync). The iOS app downloads and caches them.

> Note: the app caches downloaded models by filename (`ModelCacheManager`).
> Replacing a model's content keeps the same filename, so devices that already
> cached the old version need a cache reset (app reinstall) to pick it up.

## Security

- Only `.usdz` files are allowed; path-traversal is blocked.
- Authentication required (API Key + Firebase token) for models.

## Git

USDZ models and PNG thumbnails are **excluded from git** (`.gitignore`) due to
their size. Deploy them separately to the production server (rsync).
