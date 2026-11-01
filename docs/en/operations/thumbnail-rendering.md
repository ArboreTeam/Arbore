# Catalogue thumbnail rendering

Catalogue thumbnails are rendered by a **container job**, outside any Apple
environment. They used to be rendered from the app, screen by screen, through
a debug view — a manual operation that had to be replayed on every model
change.

That view, its RealityKit renderer and the test suite that drove it from the
simulator **have been removed** from the app (#696). The app no longer renders
thumbnails: it displays them, caches them and rejects stale ones. Rendering now
has a single path, the one described here.

## Why Blender

61 of the 123 served models exist only as USDZ. An engine that reads glTF only
would require a conversion we do not have on Linux. Blender imports USD
natively.

The version is **pinned in the image** (4.2 LTS) rather than installed by
`ops/`. Installed from the distribution, reproducibility would be the OS's and
not ours: a thumbnail must re-render identically six months from now. `ops/`
remains the source of truth for what lives **outside** containers; what lives
inside is declared in the image.

## Running the job

```sh
docker compose --profile outils run --rm vignettes
docker compose --profile outils run --rm vignettes --plantes <id>,<id>
```

The service sits behind a profile: `docker compose up -d` **never** starts it.
It is a job, not a service.

It mounts no volume and talks only to the API. Production serves its assets
from `r2` and dev from `filesystem`, so a directory mount would not work in
production. And the backend recomputes `versions.thumbnail` from the bytes it
just wrote — publishing a fingerprint that lies becomes impossible.

Render only, without publishing:

```sh
docker run --rm --entrypoint blender arbore-vignettes \
  --background --python /app/rendre.py -- \
  --modele plant.usdz --pot planter.usdz --pose '<json>' \
  --sortie thumbnail.png
```

## What the app checks, and what gets a thumbnail rejected

`PlantThumbnailCache.isLegacyThumbnail` runs four checks. A thumbnail that
trips one is **downloaded, inspected, rejected**, and the cards keep the old
image — **with nothing reporting it**. That is exactly what happened on
2026-10-30 to 123 otherwise flawless files.

| Check | Rejects when |
|---|---|
| `hasCurrentDesignMarker` | fewer than 3 of 4 corners at `(94, 28, 186)`, tolerance **5** |
| `isLegacyDarkThumbnail` | ≥ 8 opaque samples, of which ≥ 7 below brightness 55 |
| `hasLegacyWhiteWallDarkFloor` | ≥ 2 of the 5 upper samples above brightness **225** |
| `hasTopBackdropSeam` | edge > 185 **and** edge − inner > 10, at top or bottom |

Two practical consequences:

**The backdrop cannot be as light as the app's own.** `#F0EEEA`, the app
background, measures 238 — above the 225 threshold. Reusing it would get the
**whole catalogue rejected silently**. The ceiling is written into `rendre.py`
(`CIEL_CLARTE_MAX = 215`) and rendering aborts with a message rather than
producing 123 files the app will refuse.

**The job's own check must be at least as strict as the app's.** A looser check
silently lets through what the app will reject. `coins_marques` samples the
same four corners at the same 1.75 % inset and applies the same tolerance of 5.

## Non-obvious settings

None is a matter of taste; each fixes a measured defect.

| Setting | Why |
|---|---|
| `view_transform = "Standard"` | Blender 4.2 applies **AgX** by default, which desaturates. Foliage came out pale green. SceneKit applies no tone mapping. |
| Marker in `Non-Color` | The image is read and rewritten as-is. Converting the colour to linear on the assumption that writing converts back yields `(29, 3, 125)`: all 4 corners rejected. |
| `use_raytracing = False` | Enabled, the lawn bleeds onto the white planter through indirect light. Physically correct, unacceptable for a catalogue. |
| `use_shadow_jitter = True` + `shadow_ray_count = 4` + `shadow_step_count = 16` | Without them the shadow is speckled: the penumbra is approximated by blurring the shadow map, and thin foliage resolves into stair-steps. |
| Floor tint | The floor is **set dressing**: its brightness is chosen, not the result of physical lighting. Reaching it by raising the lights burns out the white planter — 2.62 % saturated pixels against 0.05 % on a served thumbnail. |
| **Emissive** backdrop | Its colour depends on neither the lights nor their distance. Lit, it would take a gradient varying with subject size: two neighbouring cards would not share a backdrop. |

## The framing is a port, not an approximation

`cadrer()` is a literal port of `PlantThumbnailFraming.fit`, depth included —
it is depth that, once the camera is pitched 8°, pushes wide plants out of
frame. Recomputing it "roughly" would give thumbnails that do not line up with
the old ones: a plant would change size from card to card depending on which
was regenerated.

One deliberate difference from the iOS engine: that one renders the **complete**
model, whose bottom IS its planter's base. The job composes a plant served
**without** a planter together with a cachepot, and the roots hang below it. So
it is the **planter's** base that meets the floor, not the bounding box —
otherwise the planter floats five centimetres above it.

## Traps hit along the way

- **`blender --version | head -1` returns `head`'s exit code**, always 0. A
  missing library passed the build and surfaced only on first run. The
  `Dockerfile` now checks links with `ldd`, with no pipe.
- **Reparenting meshes detaches the root Xform**, which carries the USD
  importer's Y-up → Z-up conversion. The planter lies down and its height
  measures `0.05865` — its radius. Reparent the **roots**.
- **A faceted silhouette is not necessarily a different model.** The cachepot
  looked square under orthographic projection with frontal lighting; in
  perspective it is round. Verified: not a subdivision matter,
  `import_subdiv=True` changes nothing.

## Measurements

Taken on 2026-10-31 on `SERVI_Chamaedorea_potless.usdz` (49 MB):

```
USD import        0.35 s
render, 64 spp    8 min 20   (under x86 emulation on an ARM Mac)
output            720 x 900, ~580 kB
clipping          0.05 %  (identical to the served thumbnail)
backdrop          brightness 204, flat to the pixel
```

Render time is **to be re-measured on the VPS**, which is natively x86: under
emulation it means nothing in absolute terms. The ratio does hold: raising
shadow quality took the render from 4 min 47 to 8 min 20.

## How the job authenticates

Through **two keys**, and no Firebase session.

```
X-API-Key              ARBORE_API_KEY        picks the database (prod or test)
X-Arbore-Internal-Key  ARBORE_INTERNAL_KEY   opens the /internal/* routes
```

Three routes, and nothing more:

| Route | Why |
| --- | --- |
| `GET /internal/plants` | know which plants to render |
| `GET /internal/models/:filename` | download the USDZ model |
| `POST /internal/models/thumbnails/:plantId` | upload the rendered thumbnail |

### Why not a service account

The first version aimed at the app's own routes, under `protected`: API key
**then** Firebase session. A robot cannot hold a Firebase session, so the only
way through was a **service account carrying the administrator role** — a human
account repurposed, with its password kept in the secret store, its token to
refresh, its UID in `ARBORE_ADMIN_UIDS`, and the right to write the entire
catalogue. To upload images.

An **anonymous** session solves nothing: it would be enough to read, never to
publish, since its UID changes on every sign-in and therefore cannot appear in
`ARBORE_ADMIN_UIDS`.

The `/internal/*` routes grant exactly the three gestures needed. They confer
**no role**, open no account route, and require both keys **together**: the API
key alone, the one the iOS app carries, does not get in.

### Key absent: the door closes

With `ARBORE_INTERNAL_KEY` unset, the internal routes answer **503
`INTERNAL_ROUTES_DISABLED`**, whatever is presented to them. An instance that
runs no robot has nothing to configure, and the surface does not exist there —
which is production's situation today.

An unset secret must **close** the door, never open it. The trap is a precise
one: `ConstantTimeCompare(supplied, configured)` would judge an empty header
equal to an empty key, and anyone would walk in. A test pins this by name.

503 rather than 404, because a 404 would be indistinguishable from the one a
mismatched host already returns — and we have chased the same fault twice
already.

The `GET /models/:filename` handler is **mounted twice**, under `protected` and
under `/internal`, from a single body (`servePlantModel`). Two copies would have
meant two definitions of the path checks to keep in agreement.

## Driving it from the workshop

The workshop exposes a `Vignettes` page showing what each environment
**serves**, and letting you redo it. The web container has no Docker access,
and rightly so: it **enqueues**, a **worker** consumes — the pattern already in
place for meshes.

```
workshop  --[POST /api/generator/vignettes]-->  queue
                                                 |
                      vignettes-ouvrier  <-------+  (--surveiller)
                               |
                               +--> renders, checks,
                               |    POST /internal/models/thumbnails/<id>
                               +--> delivers or reports failure
```

### Starting the worker

```sh
docker compose --profile vignettes up -d vignettes-ouvrier
```

It needs `ATELIER_BASE`, `ATELIER_CLE` and `ARBORE_ENV_NOM`.

**A worker serves exactly ONE environment.** While idling it carries **no**
backend key at all: the workshop attaches the API address and its two keys to
the task it hands out. `ARBORE_ENV_NOM` only decides which queue it draws from,
and `prendre` filters on that name — without the filter, a dev worker would
reserve a prod task, blocking it for twenty minutes.

A worker wired to dev therefore never, at any moment, holds the means to write
to production. This is not a rule someone could forget to follow: it never
receives the secret.

The worker is capped at 2 cores. A Blender render takes everything it is given,
and a catalogue pass runs for hours: uncapped, it starves the backend sharing
the machine.

### Declaring environments

`VIGNETTES_ENVIRONNEMENTS`, a JSON array, preferably mounted via
`VIGNETTES_ENVIRONNEMENTS_PATH` — an environment variable is readable with
`docker inspect`, a mounted file is not.

```json
[{ "nom": "dev",
   "api": "https://api-dev.arbore.app",
   "apiInterne": "http://backend:8080",
   "cle": "…", "interne": "…" }]
```

### Two addresses, and they must stay distinct

`api` is the **public** address. It builds the image URLs, and it is the
**browser** that loads those — the browser cannot reach `http://backend:8080`.

`apiInterne` is the one used for `/internal/*` calls, made by the server and by
the worker. When empty, it falls back to `api`.

Conflating them put **Cloudflare in an internal robot's path**. Measured on dev
on 2026-11-02, same keys and same URL:

```
curl/8.5.0          -> 200
Python-urllib/3.11  -> 403
```

The worker therefore took a **403 on every task**. Spoofing its agent would
have worked around a bot rule by pretending to be something else, and the rule
can change tomorrow. Traffic from a robot running on the **same machine** as the
backend has no reason to leave it: `http://backend:8080` never leaves the Docker
bridge, skips the CDN, and saves a 2.6 MB download and one upload per plant —
times 123.

The worker also announces an agent that names it. That is not the fix, since it
no longer crosses a CDN; but a robot should name itself, and "Python-urllib"
says nothing about who is calling.

`cle` is the environment's API key, `interne` its internal-routes key. **Both**
are required, and neither leaves the server — never a `NEXT_PUBLIC_`.

An entry without `interne` is still **loaded**, with an empty key, and the
preview says so plainly. Rejecting it would turn it into an "unknown
environment", a diagnosis far harder to trace back to its cause.

**Images** need no secret: `GET /models/thumbnails/:filename` is a public
backend route.

### What the page cannot do

**Compare the same plant across two environments.** Measured on 2026-11-01, the
dev (`arbore_dev`) and prod (`arbore`) catalogues each hold 123 entries and
share **no** plant identifier at all. The page therefore shows one environment
at a time, with its own entries. See #434.

> The dev database is named by `MONGODB_DB`, **not** by the default database of
> `MONGODB_URI` — that one points at `arbore_test`, a third database of 143
> entries nobody serves any more. Querying the URI without honouring
> `MONGODB_DB` measures the wrong catalogue.

### The queue is separate, and must stay that way

Thumbnail tasks live in `etat.vignettes`, **not** in `etat.taches`.
`prendre()` returns the first `en_attente` task in `taches` without filtering:
a thumbnail task placed there would be reserved by the Colab worker, which
would fail on it.

The reverse trap is silent. `lire()` rebuilds state from an explicit list of
keys and **discards everything else**, then `ecrire()` writes the rebuilt
object. A `vignettes` key missing from that list would be erased on the first
mesh deposit — that is, by the Colab worker's normal activity. The key is
declared in `lire()` **and** in `VIDE`, and a test proves it: removing the key
fails seven tests.

Thumbnail expiry is 20 min, not the meshes' 30: those are sized around a Colab
session dying and a blocking CUDA call. And it is **one task per plant** — a
single batch covering the catalogue would exceed expiry and be re-queued while
still running, putting two workers on the same job.
