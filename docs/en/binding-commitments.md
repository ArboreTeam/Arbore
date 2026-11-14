# What the Terms promise, and what upholds it

Since **version 2.3** of the terms of service, Arbore no longer merely
disclaims liability: it **describes its own behaviour**. Three clauses state
how the app conducts itself, and a fourth commits to a timing.

Those sentences are true only because code behaves a certain way and interface
elements are shown. Remove one of them and the contract becomes false — and
**no test will fail**.

This page is the list of those dependencies. It is for whoever adds plants to
the catalogue, and whoever redesigns a screen.

## The table

| The clause says | What upholds it | Checked by |
|---|---|---|
| "household safety filters exclude what is **known** to be harmful, not what has yet to be established" | `PlantCatalogContext.appendSafetyCriterion`: a `nil` verdict goes to `missing`, never to `positive` | `PlantSafetyOutcomeTests` |
| "a plant whose toxicity has not been established **is flagged as such**" | `PlantCatalogView` renders `AR_CATALOG_MISSING_PET_TOXICITY` in the "Information to confirm" section, orange icon | **nothing** |
| "the absence of a flag is not confirmation that it is safe" | the closed vocabulary: `unknown` never becomes `safe` (`Plant.swift`, lenient decoding down to the floor) | `PlantToxicityVerdictTests` |
| "every verdict is taken from a named, dated base" (`TOXICITY_DISCLAIMER_BODY`) | `TOXICITY_SOURCE_AND_DATE` under the verdict; in the database, `detail` and `evidence` go together | `ConsentDocumentVersionTests` (versions), `test_verser_toxicite` (pouring) |
| "any material change will be flagged **before it takes effect**" | `AppConfig.termsVersion` / `privacyPolicyVersion`, the `consents` registry, and `guestAcceptedDocuments` comparing versions | `ConsentDocumentVersionTests` |
| acceptance is an **act**, not a use | `hasAcceptedDocuments` governs the three account paths; `GuestAcceptanceSheet` governs guest entry on both screens | **nothing** |

Two rows carry **nothing** in the right-hand column. They are the two this
document exists to protect: they rest on an interface element, and an interface
element is removed without a sound.

## When adding plants

The underlying rule: **a value is transcribed, not inferred.** See
[`operations/botanical-data-audit.md`](operations/botanical-data-audit.md) for
the acceptance criteria, and
[`operations/chaine-plante.md`](operations/chaine-plante.md) for the path.

What belongs to this page:

- **No named source, no prose.** A verdict may stand without a source —
  `toxic` and `unknown` assert no safety. The detail may not: it is a wording,
  and serving it without saying where it comes from is borrowing a rendition
  rather than citing a fact. `verser-toxicite.py` refuses it at the boundary.
  See [`operations/asset-provenance.md`](operations/asset-provenance.md).
- **An unsourced `safe` is refused**, and must stay refused. It is the only
  value that ASSERTS safety.
- **`unknown` is not a filling defect.** An entry with no verdict is served,
  flagged, and that is the intended behaviour. Completing it at all costs to
  "look tidy" is exactly what the clause forbids.

## When redesigning

Three elements **carry the contract**. Moving them is free; removing them is
not.

**The "Information to confirm" section of the AR catalogue.** It is what makes
"is flagged as such" true. A redesign that folds it into a generic footer, or
hides it behind a disclosure, removes the flag without removing the clause.

**The source line under each verdict.** "Source: X — reviewed on Y" is what
distinguishes an attributed fact from a claim by the app. Without it, the terms
promise a traceability the screen no longer shows.

**The acceptance checkbox.** It governs four paths: email sign-up, Apple,
Google, and guest entry. The last goes through `ContinueAsGuestButton`, shared
between the sign-in and sign-up screens — deliberately, since a door locked on
one side only locks nothing.

> **The redesign trap: a new entry point.** Adding an authentication button —
> another provider, a deep link, a trial path — creates a path the checkbox
> does not govern. Nothing will flag it. Every new entry point must go through
> `hasAcceptedDocuments` or through the acceptance sheet.

**An open arbitration, not to be rediscovered twice.** On the sign-in screen,
Apple and Google can create an account on a first sign-in, with no checkbox.
They are not governed: that screen serves mainly to reconnect existing
accounts, whose acceptance is already in the registry, and "first sign-in" is
indistinguishable from "reconnection" before the fact. It is the last creation
path without a positive act, and it is known.

## If a clause changes

The terms live in two places: `terms.html` in **Arbore_SiteVitrine** is the
reference document, the app's `TERMS_*` strings mirror it.

**Both move up in version together.** A legal document whose content changes
without its version moving is no longer enforceable — that was the defect
recorded in #822, and `AppConfig.termsVersion` exists so that the version
follows the text all the way into the consent registry.

Changing a clause in this table without changing the code it describes produces
a false statement in a contractual document. In that direction too, no test
will fail.

## See also

- [`operations/asset-provenance.md`](operations/asset-provenance.md) — where the data comes from, and under what regime
- [`operations/botanical-data-audit.md`](operations/botanical-data-audit.md) — the acceptance criteria for a value
- [`screens/plant-catalog.md`](screens/plant-catalog.md) — the screen that carries the flag
- [`flows/auth-signup.md`](flows/auth-signup.md) — the account creation paths
