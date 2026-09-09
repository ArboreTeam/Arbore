# Botanical data audit

## Current baseline

Audit of the production `arbore.plants` collection, taken on September 9, 2026:

```
124 catalog plants
123 now carry a botanicalProfile
  0 plants certifiable on critical constraints
  0 verified values out of 1,860 possible
```

Four fields were populated on September 9 (#489):

| Field | Coverage | Provenance |
|---|---|---|
| `petToxicity` | 38/124 | ASPCA, named and dated source |
| `directSunHours` | 121/124 | derived from `sun.durationPerDay` |
| `wateringIntervalDays` | 107/124 | derived from `water.frequency` |
| `drainage` | 110/124 | derived from `soilAndPot.substrate` |

**"0 verified values" remains exact, and that is not a contradiction.** The audit
only accepts `reliability: high`, which this document reserves for review by a
horticulturist or botanist — step 5 of the population plan. None of these values
has been reviewed by a human.

The vocabulary says so:

| Value | Meaning |
|---|---|
| `high` | reviewed by a competent human — **none to date** |
| `authoritative` | authoritative source, machine-collected (ASPCA) |
| `authoritative-genus` | same, but the verdict holds for the genus, not the species |
| `derived` | transcribed from the plant's own prose |

> ⚠️ **One nuance to settle.** Step 3 of the plan asks to complete fields
> "**without inferring** a missing value from the text". The three `derived`
> fields transcribe an explicitly written number — "6–8 h / jour" becomes
> `{minimum: 6, maximum: 8}` — rather than inferring one. The line is thin and
> deserves a ruling: these values may be kept as hints, or removed if the rule
> is to be strict.

The engine must therefore still show at most **Probably compatible**. Legacy
prose and `PlantFlags` remain weak hints and can never produce **Suitable**.

## What the filters already consume

Independently of certification, two iOS filters read this data:

- **safety** (#488) — `botanicalProfile.petToxicity` first, `flags.toxicToPets`
  next. An **unestablished** toxicity **excludes** the plant when the user asks
  for safe plants: 40 of 124 remain in that case;
- **difficulty** (#485) — `care.difficulty`, never populated to date, then
  `flags.easyCare`. Here the unknown **does not exclude**.

The two rules differ deliberately: hiding a harmless plant denies a choice,
offering a toxic one breaks a promise.

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
7. Extend the protocol to all 124 plants, then schedule periodic review.

AI may prepare drafts and reconcile sources, but it must never invent a value or assign itself `high` reliability.
