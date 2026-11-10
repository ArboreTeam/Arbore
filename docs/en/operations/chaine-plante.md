# From collection to a served plant

This page describes the chain **end to end**: how a plant goes from a collection
entry to a 3D model placeable in augmented reality, with its data and its
thumbnail, on the development environment.

Each segment has its own detailed page; this one states **the order, the
dependencies, and what blocks what**. It exists because that information was
nowhere: reconstructing the sequence required querying the server.

```
collection → research corpus → agent enrichment → translation
                                      ↓
                        workshop queue → GPU worker
                                      ↓
                               HUMAN REVIEW
                                      ↓
                        cut · USDZ · LOD (CPU)
                                      ↓
                        Mongo import → thumbnails
                                      ↓
                            dev deployment
```

**One rule runs through the whole chain**: a value comes from a named, dated
source, or it does not exist. Never from prose, never from a guess. That is the
point of #792, and an absent value says `unknown` — it is not filled in.

---

## 1 · Collection

The entry point of the chain produces, per plant, **one reference image** and
**a set of structured attributes**. Those are the only two things downstream
needs.

The image serves twice: it feeds the 3D generator, and it is what the user sees
in the catalogue before a thumbnail is rendered.

The useful attributes, ordered by what they unlock:

| attribute | what it enables |
|---|---|
| name and **Latin binomial** | the key to everything else: matching against horticultural databases |
| **adult height** | placement at the right scale in AR, and the `size` bracket |
| exposure | the light filter and automatic placement by brightness |
| typology (habit, uses) | `kinds` and `goals`, as closed values |
| flowering period | the `flowering` trait, including its explicit `no` |
| planting distance | outdoor placement density |

**Two measured collection traps**, which cost later:

- **an image that is too small does not reconstruct.** Below 400 px on a side,
  the generator invents more than it reconstructs: measured on a 167×200
  thumbnail that produced three floating plants. Usable images are 760×760;
- **a truncated name breaks matching silently.** A 64-character name against a
  model expecting 65 raises no error: the plant and its model simply never find
  each other.

Converting attributes into structured values happens **here, at the boundary** —
"20 to 30 cm" becomes `{minimum: 20, maximum: 30}` once, with its provenance
attached. See [the botanical data audit](botanical-data-audit.md) for why that
conversion belongs nowhere else.

## 2 · Agent enrichment

Collection does not give everything. Three families of data come from
**external horticultural databases**, queried by research agents:

| axis | authoritative source |
|---|---|
| pet / child toxicity | named toxicology database, verdict as a closed value |
| colours (flower **and** foliage) | NC State Extension Gardener Plant Toolbox, Missouri Botanical Garden |
| watering interval | university extensions (Clemson, Iowa State, UAEX) |
| missing adult height | NC State, MOBOT |

### The method, and what it cost to learn

**Index, do not keyword-search.** NC State's `sitemap` gives 18,196 taxon slugs,
often at cultivar level: fetching it and walking it locally beats successive
searches.

**The cultivar decides, not the species.** *Photinia* × *fraseri* is not red,
'Red Robin' is. *Thuja occidentalis* reaches 15 m, 'Smaragd' stops at 4.
Searching at species level when the cultivar is known gives a wrong answer that
looks right.

**Half the work is refusing.** In the colour batch, 28 groups mentioned "silver"
or "bronze" on their page without the colour being on the visible face:
underside, vein, autumn colour, bark, or a cultivar other than the record's.

### Three technical traps not to rediscover

1. **Three MOBOT records return a CAPTCHA, not a 404.** The HTML contains
   "Complete the puzzle to continue" and parses to **zero fields**, therefore to
   "the database is silent". Without a guard, one concludes absence for taxa the
   database documents. Taxonid 276162, 276164, 276174.
2. **MOBOT's Plant Finder has two entry points and only one works.**
   `PlantFinderListResults.aspx?basic=<q>` returns results;
   `PlantFinderSearchResults.aspx` returns a systematic 500. And the search
   accepts only one or two words.
3. **RHS is a single-page application.** Its HTML contains no plant name and its
   API returns 404: unusable without a browser.

### A ceiling that is not a gap

Serious databases **decline to publish a watering calendar**, and that is their
position, not a hole. Clemson HGIC, verbatim: "A common question from gardeners
is 'How often should I water my plants?' **There is no pat answer to this
question.**" Measured: 320 RHS growing guides probed, 22 exist, **only 3** give
an interval in days.

Values therefore come from **watering classes the sources define themselves** —
trees and shrubs, perennials, cacti, orchids, herbs — not from per-species
verdicts. Hence the dominant `low` reliability on that axis: it says exactly
"named source, unnamed taxon".

### Writing without losing anything

Several agents write to the same files. The pattern that holds:

- **re-read immediately before writing**, set only your own key, re-read after;
- **never overwrite** a value already set;
- **verify by hash** that the translation block has not moved.

That last point is not decorative: these files carry 2.8 million characters of
translation that a careless write would lose.

## 3 · Translation

Records are written in English, then translated into French, Spanish and German
**by agents**, never by a machine translation service.

The reason is substantive: a plant record carries species names, units and
toxicity verdicts. Machine translation rephrases them without knowing which are
closed terms, and a rephrased verdict is no longer a verdict.

**A translated field never decides anything.** That is the gain from #792:
filters, scores and verdicts read closed values, identical in every language. A
plant not translated into the reader's language must be filtered **exactly
like** a translated one.

## 4 · The workshop and the worker

See [the 3D workshop](3d-workshop.md) for detail. The three properties to keep
in mind here:

**Control is inverted.** The GPU worker has no execution API: the workshop holds
a queue, and the worker comes to draw from it. Nothing is pushed.

**The expensive artefact is produced once.** The GPU mesh is stable; everything
downstream is replayable CPU work. The day pot removal improves, it is replayed
without regenerating.

**A quality gate rejects before spending.** A degenerate shape — a "slab" —
makes remeshing pathological: measured, three attempts at 3060, 4077 and 2123
seconds, all rejected afterwards. A healthy attempt from the same batch: 405
seconds. The gate therefore measures planarity **on the raw mesh, before any
texturing**.

## 5 · Human review

**This is the chain's only human intervention, and it answers two questions at
once**: is the plant valid, and which pot cut should be kept?

The previews and cut candidates are produced **before** the review precisely for
that. An invalidated plant returns to the queue with a fresh seed; a validated
one moves to the CPU downstream.

This is the chain's real bottleneck: the GPU produces faster than a human
decides.

## 6 · Cut, USDZ and levels of detail

CPU work, replayable. Three outputs:

- the **cut** mesh (without its original pot), so a user's cachepot can be
  placed underneath;
- conversion to **USDZ**, the format SceneKit reads;
- the **levels of detail**, a light model and a heavy one, swapped by distance.

A known trap: SceneKit requires **direct** texture binding in the USDZ. A file
produced through a glTF round trip yields grey plants.

## 7 · Database import

Through `appliquer-ops-mongo.py`, never by hand. Its guards, each born of an
incident:

- **`--base` is mandatory with no default**, so a slip never targets production;
- **without `--appliquer`, the script only counts** what it would do;
- **the URI does not pass through the command line**, so it appears neither in
  history nor in `ps`;
- **an operation whose filter matches nothing is reported**, not silently
  ignored: that is the symptom of a catalogue that moved;
- **the script is replayable.**

### Never overwrite

An import that overwrites impoverishes while claiming to enrich. Measured: when
importing the corpus into the served records, **146 values were kept** because
they already existed and were better populated than the source.

### A field that describes is not a field that decides

`environments` (indoor / outdoor) was imported and then **removed**. The reason
is worth keeping: it is a **commercial classification**, not a botanical fact,
and the engine gave it the power of a **critical conflict**, its harshest
verdict. On a balcony it excluded 75 plants out of 123 at a stroke, including
succulents that live there perfectly well.

Before importing a field, ask: **does it describe the plant, or decide in its
place?**

## 8 · Thumbnails

See [thumbnail rendering](thumbnail-rendering.md). Two things:

**After the import, never before**: a thumbnail is named after the record, and
the script targets it by `_id`.

**One worker serves one queue**, its own environment's. Two workers drawing from
the same queue produce wrong fingerprints.

## 9 · Deployment

See [environments](environments.md). The summary:

```sh
cd <root> && ARBORE_ENV=dev ARBORE_DEPLOY_BRANCH=dev ./deploy.sh
```

**Three traps, all encountered for real:**

- **`ARBORE_DEPLOY_BRANCH=dev` is mandatory.** Without it the script refuses,
  because its default is `main`;
- **no `sudo`.** The visible symptom is gone, the reason is not: under `sudo`,
  `$HOME` is `/root`, the decryption key cannot be found, and the deployment
  **reports success while running on the old secrets**;
- **wait for the images to be published.** Otherwise the script silently falls
  back to a local build, and what runs is no longer what CI produced.

**The only proof a deployment happened is the served commit:**

```sh
curl -s https://<api>/health | jq -r .commit
```

Not the script's output. A workflow named "Deploy" led everyone to believe
production followed its branch for weeks, while it was fifteen commits behind,
one of them a security fix.

---

## What blocks what

| to obtain | you first need |
|---|---|
| a 3D model | an image at least 400 px on a side |
| placement at the right scale | the **adult height** |
| the `size` bracket | the adult height (it derives from it) |
| a plant offerable in the wizard | its **toxicity established** on the requested axis |
| scores that differ | several axes populated, not one |
| a thumbnail | the record in the database |
| a served USDZ | the human review |

The last line is the costliest: **everything downstream waits on a human.**
