# Asset provenance

Arbore displays photographs, 3D models and botanical data it did not all
produce. This page says where each one comes from and under which terms we use
it.

It exists because the question came up at the worst moment: while filling in
**Content Rights** in App Store Connect, a form that has you declare you hold
the rights to any third-party content displayed. No written source could answer
it at the time. The repository is proprietary, all rights reserved, and had
never recorded what it borrows.

## The table

| Asset | Where | Origin | Terms |
|---|---|---|---|
| Garden style photographs | `ArboreUi/ArboreUi/Assets/Assets.xcassets/StylesImages/` | **Unsplash** | Unsplash License |
| Plant catalogue images | catalogue | **Unsplash** | Unsplash License |
| Plant 3D models (`.usdz`) | outside the repo, served by `GET /models/:filename` | **generated under a paid contract** | owned |
| Plant thumbnails | rendered off-device by a Blender job, from the 3D models | derived from the above | owned |
| Toxicity data | `Plant.Flags.ToxicToPets` / `ToxicToChildren` | **ASPCA** | facts, attributed |
| Climate estimate | `ArboreBackend/climate.go` | in-house | `Attribution` field |

## What the Unsplash License allows, and what it forbids

It grants **free use, including commercially, with no attribution and no prior
permission**. That is what makes the App Store declaration accurate: we do hold
the necessary rights.

Two limits, which Arbore does not cross:

- **reselling the photographs as they are** — we sell nothing;
- **building a service competing with Unsplash** by compiling its photos.
  Illustrating four garden styles in a questionnaire is not one.

One point that matters going forward: **`UNSPLASH_ACCESS_KEY` has been dead
since the AiGenerator was removed (#558)**. The images are *embedded* in the
bundle and in the catalogue; there is no API call left at runtime. No
third-party terms can therefore change under us on content already shipped.

## The 3D models

Generated under a paid contract from images, then optimised in-house
(`optimize_models.py`, plus the SceneKit texture-binding fixes). They are not
versioned — too large — and are deployed out of band to object storage, see
[`asset-storage.md`](asset-storage.md).

## The toxicity data

It comes **not from the entries' prose** but from structured flags, the only
sourced ones, and the app shows the source to the user:

```go
// catalog_context.go
b.WriteString("- ⚠️ Toxique pour les animaux domestiques (source ASPCA)\n")
```

These are attributed scientific facts, not a borrowed work. Abstaining there is
a decision rather than an oversight (#489): with no flag, we say nothing rather
than wrongly reassure.

### What this claim covers, and what it does not

It covers what is **served**. Measured on 2026-11-14 against `arbore` and
`arbore_dev`: 274 entries, 542 verdicts, no document carrying a prose field
taken from an external layout, and the 24 verdicts with no named source are
**all `unknown`**. The invariant holds on both sides.

The out-of-repository research corpus offers no such guarantee. It may carry
fields shaped after an external base's presentation — and with no source
recorded. As long as it is not poured in, the catalogue stays clear; but it is
the **pouring** that must check this, not the review.

**Rule: no named source, no prose.** A verdict may stand without a source —
`toxic` and `unknown` assert no safety, so they have nothing to support, and
dropping a warning for want of a source would make the catalogue less safe
rather than more honest. An unsourced `safe` has long been refused: it ASSERTS.

The detail is not of the same order. Composed of fields shaped after an
external base's presentation, it is a wording and not a fact: serving it
without saying where it comes from is borrowing a rendition rather than citing.
`verser-toxicite.py` therefore writes it only when a source has been retained,
and the invariant reads both ways — `detail` and `evidence` are present
together or absent together.

The guard lives at the boundary, like the one on name matching (see
[`botanical-data-audit.md`](botanical-data-audit.md)), not at review time.

An attributed rewording remains an attributed fact; a borrowed wording with no
source does not. Attribution is what makes the difference, and it is checked at
the boundary.

## If an asset changes

Any image or model added must appear in the table above **before** it ships. A
provenance that can no longer be reconstructed is a provenance lost: files do
not carry their origin, and team memory does not last six months.

App Store Connect's **Content Rights** declaration is not revisited on every
version — it stands until changed. Introducing an asset whose rights are unclear
would make it false without any screen warning you.

## See also

- [`app-store-release.md`](app-store-release.md) — where that declaration is filled in
- [`asset-storage.md`](asset-storage.md) — how the 3D models are served
- [`../../appstore-listing.md`](../../appstore-listing.md) — the App Privacy answers
