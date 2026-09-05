# Botanical data audit

## Current baseline

Read-only audit of the production `arbore.plants` collection, performed on July 23, 2026:

- 124 catalog plants;
- 0 `botanicalProfile`;
- 0 plant certifiable on critical constraints;
- 0 verified values out of 1,860 possible values (124 plants × 15 fields).

The engine must therefore show at most **Probably compatible** until profiles are populated. Legacy prose and `PlantFlags` remain weak hints and can never produce **Suitable**.

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
