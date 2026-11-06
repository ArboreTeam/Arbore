# The 3D workshop — how a plant is made

> Measured and verified on 2026-11-06. The workshop had existed since #609
> without a document: how it worked lived in issues (#600, #609, #623, #638,
> #681, #682, #684), which meant reconstructing it from memory every time.
> This document pins it down.

## What it is

A **protected route of `web.arbore.app`**, not another service. TLS,
authentication and an origin firewall locked to Cloudflare are already there:
an extra service would be one more attack surface, and one more oversight the
day of a hardening pass.

It turns a **plant image** into a **3D model served by the app**, with a single
human step: the review.

## Control is inverted

**Colab pulls the work.** It has no execution API, and browser-driving
workarounds break at the first interface change. The workshop therefore never
pushes: it holds a queue, and the worker comes to draw from it.

```
workshop queue → GPU worker (Colab) → quality gate → retry, fresh seed ↺
                                           ↓ accepted
                          CPU: previews + pot cut candidates
                                           ↓
                             HUMAN REVIEW: validate? which cut?
                        ↙ invalidated                   ↘ validated
             back to the queue, another seed    CPU: cut, USDZ conversion, LOD
```

Two properties carry everything else:

- **a single human step.** Previews and cut candidates are produced *before*
  the review, so that one look answers both questions;
- **the expensive artefact is produced once.** The GPU's GLB is stable; all
  downstream work is replayable CPU. The day pot removal improves, it is
  replayed without regenerating.

## Where things live

| | path | contents |
| --- | --- | --- |
| work area | `GENERATOR_DATA_HOST_PATH`, i.e. `data/generator` | the workshop's whole state |
| state | `data/generator/etat.json` | `taches`, `plantes`, `pots`, `sources`, `empreintes`, `vignettes` |
| per plant | `data/generator/plantes/<Name>/` | `<Name>.glb`, `sanspot_*.glb`, `apercu_*.png` |
| ready cuts | `data/generator/sortie_light/` | one GLB per recut plant |
| served models | `arbore-data/models-<env>/` | USDZ served by the backend, `heavy/` for heavy LODs |

The workshop lives on the **dev** stack, not on production: that is where trial
iterations belong. Exactly one workshop exists, deliberately.

## Reading `etat.json` without getting it wrong

This is the main trap, and it is expensive.

### `verdict` — the judgement on the PLANT

`validee`, `invalidee`, `ecartee`, or absent. Measured on 2026-11-06 across 78
plants: 67 validated, 7 invalidated, 2 discarded, 2 without a verdict.

### `coupe` — the judgement on POT REMOVAL

Carries the name of the accepted file, `sanspot_geometrie.glb` or
`sanspot_couleur.glb`.

> ⚠️ **Its absence records a REFUSAL, not an oversight.** The `sanspot_*.glb`
> files left on disk are the **rejected** attempts. The workshop keeps them.

On 2026-11-06 I concluded the opposite: seeing three validated plants with a
`sanspot_*.glb` on disk but no declared `coupe`, I took it for a mismatch
between file and disk, and announced them as "the most advanced of the lot,
all they need is the conversion". Converted and then opened, two showed an
intact, torn pot and the third a severed trunk. **Only `coupe` is
authoritative; a file's presence says nothing about its quality.**

### The two cutting methods

| | what it does | chosen |
| --- | --- | --- |
| `sanspot_geometrie.glb` | separates by geometry | **52 times out of 58** |
| `sanspot_couleur.glb` | separates by colour | 6 times |

Verified on a two-candidate case (Washingtonia): `geometrie` keeps the trunk,
`couleur` mistook it for the pot and removed it. The split is therefore not
arbitrary.

## Thumbnail workers — one per QUEUE

Not to be confused with the Colab worker, which generates meshes. These render
the catalogue **thumbnails**, under Blender.

A worker serves **exactly one queue**, the one named by its `ARBORE_ENV_NOM`;
the code refuses to start without it. The workshop, in contrast, holds as many
as it declares environments in `VIGNETTES_ENVIRONNEMENTS`.

```
ARBORE_PROFILS=vignettes,vignettes-prod

  arbore-dev-vignettes-ouvrier        ARBORE_ENV_NOM=dev
  arbore-dev-vignettes-ouvrier-prod   ARBORE_ENV_NOM=prod
```

Both live on the stack carrying the **workshop**. It is the workshop that would
be harmful in duplicate: two `etat.json` files, and the "which one is right?"
question had produced 54 wrong fingerprints. Two workers drawing from the same
workshop have no such problem.

How they work, the network attachment they require and the fingerprint checks:
[`thumbnail-rendering.md`](thumbnail-rendering.md).

## From cut to catalogue

A validated plant is not yet shippable. It needs, in this order:

1. **a `taille`** — the specimen's real height, set at review. Without it, no
   `heightMeters`, hence no true-to-scale placement;
2. **an accepted `coupe`**, if a pot-less plant is wanted;
3. **the GLB → USDZ conversion** via
   `Plant3DGenerator/usdz_sans_reduction.py`, which reduces nothing (decision
   of 2026-10-22) and does only what ARKit requires: **direct** texture binding
   against the grey bug of #292, `subdivisionScheme = "none"`,
   `usdzip --arkitAsset`. Requires `usdcat` and `usdzip`;
4. **a measured `potBase`**, without which the backend serves no pot, by
   design;
5. **the catalogue operations**: `modelURL`, `potless`, `hasHeavy`,
   `heightMeters`, `versions.model`;
6. **the thumbnail**, rendered and published through the internal route so the
   backend computes its fingerprint itself.

The produced file's naming follows the rule of #773, documented in
[`../3d-lod-architecture.md`](../3d-lod-architecture.md): the name says what the
file **is**, `<Name>.usdz` with its pot, `<Name>_potless.usdz` without.

## What a plant record requires

The workshop only produces the mesh. The record carries far more, and its
schema is documented in
[`../architecture/04-data-model.md`](../architecture/04-data-model.md),
`plants` collection. In summary, per plant:

| | field | note |
| --- | --- | --- |
| identity | `name`, `type`, `description`, `imageURLs` | |
| 4 languages | `translations` | `fr`, `en`, `es`, `de`; each carries description, type, sun, water, soil and pot, health, life cycle, care |
| recommendation | `flags` | 12 booleans feeding the wizard |
| horticulture | `botanicalProfile` | 15 facts, **each with its provenance** (`sourceName`, `sourceURL`, `reviewedAt`, `reliability`) |
| 3D | `modelURL`, `potless`, `potBase`, `hasHeavy`, `heightMeters`, `versions` | |
| provenance | `source`, `sourceUrl` | |

> ⚠️ **Toxicity appears in two places, and they do not play the same role.**
> `flags.toxicToPets` and `flags.toxicToChildren` are booleans that **filter**
> the wizard's recommendation; `botanicalProfile.petToxicity` and
> `childToxicity` are **sourced** facts shown to the user. The first decide,
> the second explain. A record carrying only the second would let the wizard
> recommend a toxic plant to a household with pets.

`PlantDataEvidence` exists so that provenance is carried **per value**, not per
record: a record is not verified because a single one of its fields has a
source.

## Measured figures, not to be relearned

| | |
| --- | --- |
| generation | ~0.3 compute units per plant, full catalogue under 2 € |
| VRAM | **10.27 GB**, against the 24 announced by the TRELLIS README |
| pot removal | **CPU only**, a few seconds |
| USDZ conversion | ~3.5 s per model, 4 models in 14 s |
| a TRELLIS's weight | 35 to 60 MB as USDZ, against 2 to 7 MB for a Meshy |
| one thumbnail render | 249 s per plant with a pot, measured over 51 |

Three avenues have been **closed by measurement** and do not reopen without
new evidence: **multi-view** generation (adds no information), **changing
engine** (would leave an MIT engine for a non-commercial stack), and the
**crumpled-pot detector** (seven criteria, none separates).

## See also

- [`thumbnail-rendering.md`](thumbnail-rendering.md) — rendering and publishing thumbnails
- [`../3d-lod-architecture.md`](../3d-lod-architecture.md) — LOD, naming, fingerprint cache
- [`../architecture/04-data-model.md`](../architecture/04-data-model.md) — the full record schema
- [`asset-provenance.md`](asset-provenance.md) — licences and provenance
