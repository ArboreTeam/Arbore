# Botanical data audit

## Current baseline

Measured 2026-11-08 on the research corpus (`BotanicScraper/data`), which
production imports as 3D models are generated:

```
1021 records carrying a botanicalProfile
   0 validator errors (BotanicScraper/valider-lot.py)
 144 records in all four languages, 877 in English only
```

| Field | Coverage | Provenance |
|---|---|---|
| `petToxicity` · `childToxicity` | **1021** | named, dated database; verdict as a closed value |
| `environments` | **1021** | closed `usages` typology (#777) |
| `kinds` | 981 | closed `port` typology (#777) + genus |
| `easyCare` | 999 | `_meta.difficulty`, three levels |
| `directSunHours` | 920 | product page "Exposition" field |
| `matureHeightCm` | 793 | "Hauteur adulte" field, normalised to cm |
| `size` | 791 | thresholds applied to `matureHeightCm` |
| `goals` | 656 | closed `usages` typology |
| `flowering` | 398 | "Période de floraison" field |
| `droughtTolerance` | 320 | "Résistant au sec" field, **positive only** |
| `plantingDistanceCm` | 258 | "Distance de plantation" field |
| `colors` | **841** | NC State Plant Toolbox, Missouri Botanical Garden |
| `wateringIntervalDays` | **627** | watering classes defined by university extensions |

**None of these values is derived from prose.** Each comes from a named
toxicology database, a structured field of the product page, or a closed
typology. That is the point of #792, and an automated guard checks it: a test
opens the fill scripts and rejects any access to `description`, `translations`
or `name`.

### Two research batches, and the ceilings they hit

**`colors` had no source in the corpus** — the `feuillage` field is free prose,
the very path #792 closes. The values therefore come from two external
databases, indexed rather than keyword-queried: NC State's `sitemap` (18,196
taxon slugs, often at cultivar level) and MOBOT's Plant Finder. The remaining
180 records are either plants **sold by colour** — the source gives six to eight
colours for a *Verbena* — or assortments **with no taxon**.

Half the work was **refusing**: 28 groups mention *silver*, *gray* or *bronze*
on their page without the colour being on the visible face — underside, vein,
autumn colour, bark, or a cultivar other than the record's.

**`wateringIntervalDays` hits a position, not a gap.** Serious horticultural
databases decline to publish a calendar. Clemson HGIC, verbatim: "A common
question from gardeners is 'How often should I water my plants?' **There is no
pat answer to this question.**" Missouri Botanical Garden: "you cannot water by
the calendar."

Measured: **320 RHS growing guides probed, 22 exist, only 3 give an interval in
days.** The values therefore come from **watering classes the sources define
themselves** — trees and shrubs, perennials, cacti, orchids, herbs — not from
per-species verdicts. That is why `low` dominates reliability on this axis: it
says exactly "named source, unnamed taxon". Searching further will not yield
more.

Two figures were refused for the same reason the old script derived badly:
"1 inch of water per week" is a **volume**, and the sub-daily frequencies found
described **the container**, not the plant.

**Reliability stays low on the horticultural axes.** Fields pulled from the
product page carry `reliability: "low"`: a merchant's figure, good for bounding
a UI handle, not for certifying. Only toxicity reaches `high`, because it cites
a toxicology database.

## What the filters already consume

Independently of certification, two iOS filters read this data:

- **safety** (#488, #787) — `botanicalProfile.petToxicity` first,
  `flags.toxicToPets` next. The fallback has two rules, and each was violated
  before #792: **a present fact decides even when it says `unknown`**, and a
  flag's `false` is not proven harmlessness. The two policies are named —
  `.browsable` shows the undetermined, marked; `.offerable` excludes it;
- **difficulty** (#485) — `botanicalProfile.easyCare` first, populated on **999
  of 1021**, then `care.difficulty`, then `flags.easyCare`. Here the unknown
  **does not exclude**.

The two rules differ deliberately: hiding a harmless plant denies a choice,
offering a toxic one breaks a promise.

**Care difficulty does not depend on the reader's language.** This page used to
describe `care.difficulty` as read "under `translations.<language>.care`", which
is still true of the fallback and is a defect of the same family as the toxicity
`detail` shown in English by #790. The closed `easyCare` value closes it for 999
records; the remaining 22 still suffer it.

## Running the audit

[`scripts/audit_botanical_catalog.py`](../../../scripts/audit_botanical_catalog.py) accepts a JSON export from `GET /plants`:

```sh
python3 scripts/audit_botanical_catalog.py \
  --input plants.json \
  --csv botanical-audit.csv
```

It can also read the protected API. Secrets stay in environment variables and must never be committed:

```sh
ARBORE_API_KEY="…" \
ARBORE_FIREBASE_TOKEN="…" \
python3 scripts/audit_botanical_catalog.py \
  --url https://api.arbore.app/plants \
  --csv botanical-audit.csv
```

The report distinguishes:

- missing fields;
- present but insufficiently sourced fields;
- verified coverage;
- plants certifiable on critical fields.

## Enrichment tools

Two scripts, to run in this order. None writes to the database: they produce
an operations file to be reviewed before applying it with `mongosh`.

```sh
# 1. Collect the ASPCA list (toxicity to dogs / cats / horses)
python3 scripts/collect-aspca-toxicity.py          # → aspca.json

# 2. Match against the catalogue and produce the operations
python3 scripts/enrich-pet-toxicity.py \
  --aspca aspca.json --plants plants.json --out ops.json
```

The expected plants file is a `GET /plants` export, as for the audit.

**One rule baked into these scripts, not to be undone:** name matching only
accepts an exact species, or an ASPCA entry in `spp.` which covers the whole
genus. An entry naming a **different** species of the same genus is rejected —
`hydrangea arborescens` says nothing about *Hydrangea macrophylla*. Without this
rule, 72 plants would receive a borrowed verdict.

### Never derive a value from prose again (#792)

A third script used to live here: `derive-botanical-profile.py`, which pulled
sun, watering and drainage from each plant's **description**. **It is deleted**,
and this page used to recommend it — meaning this page prescribed the very
practice #792 closed.

The rule that came with it deserves quoting, because it is the best argument
against the method it protected:

> "Derivation rejects any fragment mentioning centimetres: 'water when the top
> 2–3 centimetres are dry' describes a soil depth, not a periodicity. Reading it
> as 'every 2–3 days' would be a fivefold error, **invisible on review**."

The guard is sound and the trap was real. But a method whose ways of being wrong
must be enumerated is not a source. A value derived at read time cannot be
reviewed, dated or contradicted; it also depends on the display language.

**Parse at ingestion, store the result, never derive at read time.** The scraper
parses botanic's HTML and turns "20 à 30 cm" into `{minimum: 20, maximum: 30}` —
once, at the boundary, with its provenance attached. That is where parsing
belongs, and nowhere else.

## Acceptance criteria

A verified value has:

- a named source or URL;
- a review date;
- `high` reliability.

The seven critical fields tracked by the audit are indoor/outdoor environment, minimum temperature, direct sun, mature width, minimum pot volume, and pet/child toxicity. The remaining eight fields are still required for a useful and explainable recommendation.

## Population plan

1. Identify the 30 most viewed/placed plants and those carried by the first partner.
2. Confirm scientific names and remove duplicate or overly generic entries before research.
3. Populate all 15 fields without deriving missing facts from marketing prose.
4. Attach evidence per field, prioritizing recognized botanical databases, public bodies, and dedicated toxicology sources.
5. Have the batch reviewed by a horticulturist or botanist; that review date becomes `reviewedAt`.
6. Rerun the audit and only allow **Suitable** after full critical coverage.
7. Extend the protocol to all 1021 records, then schedule periodic review.

AI may prepare drafts and reconcile sources, but it must never invent a value or assign itself `high` reliability.
