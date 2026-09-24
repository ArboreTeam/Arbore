# Releasing on the App Store

TestFlight and the App Store are two distinct paths sharing a single build
repository. This page covers the second; the first is in
[`testflight-deploy.md`](testflight-deploy.md).

Written after the **1.0.0 submission on 2026-09-24**, from what actually
happened.

## What is automated, and what is not

| Step | Tool |
|---|---|
| Marketing version, build, archive, upload | `fastlane public_beta` (or `beta`) |
| Listing text, 4 languages, URLs, App Review info | `fastlane upload_metadata` |
| Screenshots, 4 languages | `fastlane upload_screenshots` |
| Attaching the build to the version | ASC |
| **App Privacy** | ASC, by hand |
| Categories, age rating, Content Rights | ASC, by hand |
| Pricing and Availability | ASC, by hand |
| Release mode, then “Add for Review” | ASC, by hand |

Both listing lanes push into the current version's **draft** and never submit
anything. They read the version from the Xcode project, so an editable version
must exist in ASC.

There is no `release` lane chaining it all. That is deliberate: the right moment
to write one is after a **second** submission, once the real shape of the
repeatable cycle is known.

## The traps, in the order they spring

### `agvtool` breaks this project's versioning

`Info.plist` references `$(MARKETING_VERSION)`: a single source of truth, and the
right setup. `agvtool new-marketing-version` **hardcodes the value into the plist
without touching the build setting**:

```diff
- <string>$(MARKETING_VERSION)</string>
+ <string>1.0.0</string>
```

The two then silently disagree. The binary carries the new version while
`get_version_number` still reads the old one, so `upload_metadata` and
`upload_screenshots` fill in **the wrong version's** listing. You only find out
when you discover an empty listing at submission time.

**Use Xcode, or edit `MARKETING_VERSION` directly.** The `Cannot find ".../NO"`
and `".../YES"` messages agvtool prints here come from the same confusion: it
looks for `INFOPLIST_FILE` and hits `GENERATE_INFOPLIST_FILE` values instead.

### The build number restarts at 1 on a new version

`latest_testflight_build_number` queries App Store Connect **for a given
version**. On a fresh version train it finds nothing and returns 1; the lane
increments to 2. After 37 builds on `0.1.12`, the first `1.0.0` therefore carries
number **2**.

That is valid: Apple only requires uniqueness and growth **within** one version
train. Nothing in the project depends on it — Sentry names its release
`<version>+<build>` and matches dSYMs by debug UUID, and no app code compares
numbers.

### Beta App Review goes from 5 minutes to ~20 hours

Apple only truly reviews the **first build of a given version**. Later builds of
the same `CFBundleShortVersionString` are fast-tracked.

Measured: builds 24 to 37, all on `0.1.12`, approved in 1 to 5 minutes. `1.0.0
(2)`, the first build of a new train, took **19 h 42**.

Expect this on every marketing-version change. **Internal** testers get the build
without waiting for that review.

### `deliver` can create duplicate screenshots

It uploads every file, then verifies they are present. Because App Store Connect
indexes with a delay, that check sometimes reports files as “missing” when they
did land. The automatic retry re-uploads them, and they **stack instead of
replacing**.

`overwrite_screenshots: true` does not protect against this: it wipes **before**
the upload, not during retries.

**Always recount after a push**; “Successfully uploaded all screenshots” is not
enough. Duplicates can be deleted through the API or in Media Manager.

### `copyright.txt` is global, and its absence blocks everything

`fastlane/metadata/copyright.txt`, at the root of `metadata/` — not a per-language
file, unlike the description, keywords and URLs. Expected format: the year the
rights were obtained, then the holder, with no URL and no symbol.

Its absence only shows on the last screen, as “Unable to Add for Review”.

### The default screenshot slot is the wrong one

The version page opens on the **6.5"** slot, which expects `1242 × 2688` or
`1284 × 2778`. Our screenshots are `1290 × 2796`, the **6.9"** slot — the only
one required since 2024.

Go through **“View All Sizes in Media Manager”**. Once uploaded, ASC shows
“6.5" Display — Using 6.9" Display”, so there is no need to export the fallback
size.

Remember to switch the **language selector** too; it opens on French.

### No iPad, no Mac, no Vision Pro

`TARGETED_DEVICE_FAMILY = 1`: no iPad screenshot will ever be requested.

For Mac and Vision Pro, ASC announces “Version X is compatible”, but that is a
build check, not a judgement on experience. Arbore rests on ARKit, the camera and
LiDAR: without them the core feature does not work. Both boxes stay unchecked.

## App Privacy

This is the riskiest part, and no tool pushes it. The answers are written in
[`../../appstore-listing.md`](../../appstore-listing.md), verified against the
code.

Three choices there require reasoning, and would otherwise be lost:

- **`Coarse Location` must be declared**, under *App Functionality* **and**
  *Product Personalization*. The rounded position genuinely changes the suggested
  list: `PlantCatalogContext` derives a hard exclusion from it before ranking.
- **`Environment Scanning` must NOT be declared**, despite ARKit and LiDAR.
  Apple's definition is “transmitting off the device”, and WorldMaps and scenes
  stay inside the app container.
- **No tracking.** No `AdSupport`, no `NSUserTrackingUsageDescription`, no
  `FirebaseAnalytics` — only `FirebaseAuth`, `FirebaseCore` and
  `FirebaseFirestore` are linked into the binary.

A declaration inconsistent with actual behaviour is a frequent rejection reason.
It happened: location was missing while the listing description announced it, on
the same product page.

## Before submitting

Release can be set to **automatic** or **manual**. On automatic, Apple approves
whenever it wants — including overnight — and the listing goes public within the
minute.

Either way, check production is ready:

```sh
curl -s -o /dev/null -w "%{http_code}\n" https://api.arbore.app/health
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://api.arbore.app/chat   # 401 expected
curl -sL -o /dev/null -w "%{http_code}\n" https://arbore.app/privacy
```

## See also

- [`testflight-deploy.md`](testflight-deploy.md) — the lanes and the TestFlight path
- [`asset-provenance.md`](asset-provenance.md) — to answer Content Rights
- [`../../appstore-listing.md`](../../appstore-listing.md) — listing text and App Privacy answers
