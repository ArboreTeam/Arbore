# Observability (Sentry)

Crash and performance reporting for Arbore. **iOS**, **web** and the **Go/Gin backend** are wired up; the Python AiGenerator remains in **Phase 2**.

- Issue: #205
- iOS SDK: [`sentry-cocoa`](https://github.com/getsentry/sentry-cocoa) via Swift Package Manager
- Web SDK: [`@sentry/nextjs`](https://github.com/getsentry/sentry-javascript)
- Org: `epi-apps` (sentry.io, **EU** data residency)
- Projects: `arbore-frontend` (iOS), `frontend-web-arbore` (web), `arbore-backend` (Gin)
- Backend SDK: [`sentry-go`](https://github.com/getsentry/sentry-go) + `sentrygin`

---

## Measured state — 2026-09-10

Read from the Sentry organization, not inferred from configuration. Re-measure
rather than trust: these figures age.

| project | SDK | state |
|---|---|---|
| `arbore-frontend` (iOS) | ✅ | **reporting since build 29** (anonymous regime, #495) |
| `frontend-web-arbore` | ✅ | 192,800 spans |
| `arbore-backend` | ✅ since #388 | panics, 5xx and startup failures |

### What the instrumentation found on day one

The 2026-09-08 reading showed "zero errors across all three projects". That was
not a sign of health, it was the measurement of what was not wired up. Two days
later the first real events delivered three defects no code review had caught:

| event | defect | issue |
|---|---|---|
| `App Hanging: 2000 ms` | plant traits recomputed on every call, on the main thread | #499 |
| first anonymous event | `device_app_hash` was leaving the device without consent | #498 |
| the same one, read closer | `user.geo` carried country **and city**, on an anonymous report | #498 |
| `App Hanging` with culprit `YourApp.$main` | it was an XCTest runner, not a user | #506 |
| — | wizard questions skippable by swiping, found validating the same build | #500 |

The second one is the one to remember: **the anonymisation had been declared
sound after a code review, and the public privacy policy asserted it the next
day.** A real event contradicted both. A review cannot see what an SDK adds by
itself.

Hence the rule that now applies to this project: **verify against a real event
after every build**, and only write into the policy what has been observed
leaving the device.

A Sentry organization `arbore` also exists, **empty**. It must not be used as a
destination by mistake: everything lives in `epi-apps`.

## iOS

| Item | Location |
|---|---|
| SDK wrapper | `ArboreUi/ArboreUi/Observability/SentryManager.swift` |
| Init (before Firebase) | `ArboreUi/ArboreUi/LoginAuth/AppDelegate.swift` |
| Config / DSN assembly | `ArboreUi/ArboreUi/Config/AppConfig.swift` |
| Secrets (gitignored) | `ArboreUi/Secrets.xcconfig` (+ `.example`) |
| Privacy manifest | `ArboreUi/ArboreUi/PrivacyInfo.xcprivacy` (CrashData + OtherDiagnosticData) |
| dSYM upload | `fastlane/Fastfile` → `beta` and `public_beta` lanes |

`SentryManager` is **disabled until a DSN is configured**. Without secrets, the
app builds and runs identically (handy for contributors and CI).

It no longer **depends on consent to start**, however (#469, #495). The
reasoning: a crash could only be observed on devices whose owners had enabled a
setting they were never offered, which amounted to observing nothing. So two
regimes coexist, and consent picks which one applies:

| | without consent | with consent |
|---|---|---|
| `user` (Firebase UID) | dropped | kept |
| `device_app_hash` | **removed** (#498) | kept |
| IP address | **replaced with `0.0.0.0`** | **replaced with `0.0.0.0`** |
| network breadcrumbs | discarded | kept |
| `tracesSampleRate` | `0` | `0.1` |
| `attachViewHierarchy` | no | yes |

In both regimes: no IP, no email, no name, no request body.

The logic lives in two pure functions, `scrub(_:consenti:)` and
`filtrer(_:consenti:)`, precisely so it can be tested — it used to sit inside a
nested closure, which is what made #498 invisible (#496). Nine tests cover it,
one of them proven by neutralisation.

### Geolocation, and why scrubbing cannot touch it

Sentry derives a country **and a city** from the IP address and puts them in
`user.geo`. This happened even on anonymous reports.

The "Prevent Storing of IP Addresses" setting is not enough: it removes the
address, not the position derived from it.

**Scrubbing rules are not enough either.** Measured on 2026-09-10, five control
events:

| what was sent | `user.geo` |
|---|---|
| no IP in the payload | `FR, France` |
| no IP + `[Remove][Anything]` rule on `$user.geo` | `FR, France` |
| no IP + rule on `user.geo` (path, no `$`) | `FR, Paris, France` |
| `user.ip_address: "0.0.0.0"` | **no `user` block at all** |
| `user.ip_address: "127.0.0.1"` | **no `user` block at all** |

The third run settles the obvious objection — that the pipeline was not running:
on that very event, `extra.password` and `extra.api_key` came back `[Filtered]`.
Scrubbing worked, the rules were active, and they did not match. Geolocation is
computed **after** the scrubbing stage: the field does not exist yet when the
rules run.

**Do not add a rule on `user.geo` again.** It would give the illusion of
protection.

**What works** is on the client, in `scrub()`: set an explicit non-routable
address instead of clearing the field. Sentry then stops guessing. `0.0.0.0` is
identical across every installation, so nothing identifying is reintroduced in
exchange.

It is counter-intuitive and worth remembering: **erasing one piece of data can
reveal another**, when the erasure hands control back to whoever can guess.

`app_id` is still sent under both regimes: it is the **binary's UUID**, identical
across every installation of a given build, and symbolication depends on it. It
designates nobody — unlike `device_app_hash`, which is per-installation.

Other options set: `environment` (`debug` / `production`, see the next section),
`releaseName = version+build`, `dist = build`, `attachScreenshot = false`
(privacy), `sendDefaultPii = false`.

### iOS setup (one-shot)

**1. DSN → `Secrets.xcconfig`.** The DSN is a `https://<publicKey>@<host>/<projectID>` URL. Since an xcconfig file treats `//` as a comment, it is stored as **three fields** reassembled in `AppConfig.sentryDSN`:

```
# Secrets.xcconfig (gitignored — never commit)
SENTRY_DSN_PUBLIC_KEY = <public key>
SENTRY_DSN_HOST       = o<org>.ingest.de.sentry.io   # .de = EU
SENTRY_DSN_PROJECT_ID = <project id>
```

Leave empty to keep Sentry disabled.

**2. dSYM symbolication (fastlane).** The `beta` and `public_beta` lanes send the dSYMs **before** the TestFlight upload. Org/project are already wired in the Fastfile (`epi-apps` / `arbore-frontend`); all that remains is to provide an auth token. Without a token, the lane logs a skip and continues.

> The order was reversed on 2026-09-10 (#511), and it is not a detail. On build
> 31, an SSL cut towards Apple during the changelog step stopped the lane 36
> minutes after a successful upload, therefore before the symbols were sent: the
> binary was with the testers and its crashes promised to be unreadable call
> stacks. A binary must never reach a tester before its symbols are at Sentry.
> The dSYM is available as soon as `build_app` finishes; nothing required
> waiting.
>
> If delivery then fails, we will have uploaded symbols for a build that does
> not exist: a few orphan megabytes, without consequence. That is the right side
> of the trade.

```bash
brew install getsentry/tools/sentry-cli
cp .sentryclirc.example .sentryclirc   # then paste the token (gitignored)
bundle exec fastlane beta
```

Create the token at `sentry.io → Settings → Auth Tokens` (scopes `project:releases` + `project:write`). Instead of `.sentryclirc`, export `SENTRY_AUTH_TOKEN`; override `SENTRY_ORG` / `SENTRY_PROJECT` via the environment if needed.

### Verify (iOS)

1. Fill in the DSN in `Secrets.xcconfig`, run a **Debug** build.
2. Profile → **Debug Tools → "Send Sentry test event"** (visible in DEBUG only).
3. The event shows up in `sentry.io → arbore-frontend → Issues` within seconds, tagged `environment: debug`. **Without consent it carries no `user` at all** — the Firebase UID is attached only if "Link diagnostics to my account" is on.
4. For symbolicated **release** crashes, ship a `fastlane beta` (or `public_beta`) build with the token above, then trigger a crash on the TestFlight build.

> ℹ️ **Tests emit nothing.** `start()` returns immediately under XCTest (#506).
> Before that fix, any machine whose `Secrets.xcconfig` carried a DSN sent a fake
> "App Hanging" on every run of the suite — the stack was the runner starting up.
> If a test event seems missing, that is expected: use the debug button above,
> not `xcodebuild test`.

**And the check that actually matters**: after every shipped build, open a real
event and read its raw JSON — `user`, the `app` context, the breadcrumbs. That
reading, not CI, is what found #498. Tests guarantee the code removes what it
was told to remove; they will never tell you nothing else remains.

## ⚠️ Environment vocabulary is not unified

The three components do not tag their events the same way. This is a known
defect, not an oversight, and it must be known before building any view or alert
filtered by environment.

| Component | Values emitted | Where they come from |
|---|---|---|
| Go backend | `prod` / `dev` | `SENTRY_ENVIRONMENT`, derived from `ARBORE_ENV` |
| Web (server, edge) | `prod` / `dev` | same |
| Web (browser) | `production` | `NODE_ENV` fallback, frozen at build |
| iOS | `debug` / `production` | `#if DEBUG` in `AppConfig.environment` |

**Two practical consequences.**

A view filtering on `production` will see neither the backend nor the web server,
both emitting `prod`. The web changed value on 2026-09-09: its earlier data sits
under `production`, everything after under `prod`.

And above all: **the iOS `Debug` and `Dev` builds report under the same label**,
`debug`, while `Debug` targets **production** and `Dev` targets
`api-dev.arbore.app`. Two different backends under one name.

Not for lack of information. `AppConfig.baseURL` reads `ARBORE_BACKEND_HOST`
from `Info.plist`, fed by the configuration's xcconfig: the app knows exactly
which backend it targets. The defect is that `AppConfig.environment` does not
look at it — it keys off `#if DEBUG`, which `Dev` inherits anyway. **Wrong
criterion, not missing information.**

That trap is now **fully armed**: since build 29, iOS reports. An event coming
from a `Dev` build is today indistinguishable from one coming from a `Debug`
build, even though they target two different backends.

---

## Web (Next.js)

`@sentry/nextjs` is wired through three configs that **no-op without a DSN** (privacy first: `sendDefaultPii: false`, no Session Replay):

| File | Runtime | DSN |
|---|---|---|
| `web/sentry.client.config.ts` | browser | `NEXT_PUBLIC_SENTRY_DSN` |
| `web/sentry.server.config.ts` | Node server | `SENTRY_DSN` \|\| `NEXT_PUBLIC_SENTRY_DSN` |
| `web/sentry.edge.config.ts` | edge | same as server |

`web/instrumentation.ts` loads the server/edge configs based on `NEXT_RUNTIME`. `tracesSampleRate = 0.1`. The error boundaries `web/app/error.tsx` and `web/app/global-error.tsx` call `Sentry.captureException`. Source map upload is opt-in via `SENTRY_ORG` / `SENTRY_PROJECT` / `SENTRY_AUTH_TOKEN` (uncommitted); when absent, the build does not fail.

### Healthcheck noise

The Docker healthcheck hits `web/app/health/route.ts` — a dedicated route, not
`/`. That transaction is excluded from tracing by `ignoreTransactions:
['GET /health']` in `sentry.server.config.ts`.

Before this separation (#469), the probe targeted `/` and accounted for
**21,880 spans out of 22,060 over 7 days — 99.2%** of traced volume, while every
real page combined totalled 180. Tracing described not the site's usage but the
probe watching it — #388's pattern on the backend, transposed to the web.

A dedicated route rather than a filter on `GET /`: the root is also the real
homepage, and filtering it would have hidden the traffic we actually want.

`force-dynamic` on the route is required — without it Next.js would prerender
it, and the probe would only test the ability to serve a static file.

### Environment tagging

`SENTRY_ENVIRONMENT` (`prod` / `dev`, derived from `ARBORE_ENV`) is read **at
runtime** by `sentry.server.config.ts` and `sentry.edge.config.ts`. One image
therefore serves both environments, each tagging itself.

The trap fixed by #469: `NEXT_PUBLIC_SENTRY_ENV` is inlined **at build time**.
Setting it on the container had no effect, `web/.env` left it empty, and the
`NODE_ENV` fallback yielded `production` everywhere — prod and dev
indistinguishable.

> ⚠️ **Remaining limit, browser side only.** `sentry.client.config.ts` runs in
> the browser and cannot read a runtime variable: its tag stays frozen at build
> time. No effect today — over 90 days the project received **no** browser
> transactions at all, every span comes from the server. Fixing it would require
> one image per environment.

## Backend (Go)

`sentry-go` + `sentrygin`, wired in `ArboreBackend/observability.go` (#388). **No-op without a DSN**, like iOS and web: a missing secret never prevents the backend from starting.

| What is captured | By what |
|---|---|
| Panics | `sentrygin` with `Repanic: true` |
| Deliberate 5xx responses | `captureServerErrors()` |
| **Startup** failures | `fatalf()` — see below |

**Middleware order is not arbitrary.** `sentrygin` is mounted AFTER `gin.Recovery()`, so Recovery is the outer handler: sentrygin captures the panic and re-raises it, Recovery catches it and returns 500. Mounted the other way round, Sentry would swallow the panic and the client would see a dropped connection.

**Panics and 5xx do not duplicate**, despite both mechanisms coexisting: a panic unwinds the stack and skips everything after `c.Next()`. `captureServerErrors` therefore never runs for a panic-induced 500.

**`fatalf` replaces `log.Fatalf` at startup.** `log.Fatalf` calls `os.Exit`, which runs no `defer`: a `defer flushSentry()` does not cover initialisation failures. Yet a backend that refuses to start is the gravest and most silent case — the container loops, no request arrives, the middleware sees nothing.

**`SendDefaultPII` is `false`, and must stay so.** `true` would attach the full IP address and headers to events, undoing the `/24` truncation introduced by [#385](https://github.com/ArboreTeam/Arbore/issues/385).

**One project, tagged by environment.** `SENTRY_ENVIRONMENT` is `prod` or `dev`, derived from `ARBORE_ENV`. Sentry filters on it natively; two projects would double the alert rules for a separation the tag already provides.

> ⚠️ The source variable is named **`SENTRY_DSN_BACKEND`**, not `SENTRY_DSN`: the web service reads the latter, and a shared name would send its server errors into the backend's project. One DSN per service, hence one variable per service.

### Access log

The router is built by `newRouterEngine()` (`ArboreBackend/httplogging.go`), **not** by `gin.Default()`. Same composition — `Logger` + `Recovery` — with two differences:

| | Behaviour | Rationale |
|---|---|---|
| **Truncated IP** | `/24` for IPv4 (`92.184.105.x`), `/48` for IPv6 (`2a01:e0a:1b2:x`), `-` when unparsable | `TrustedPlatform = "X-Real-IP"` resolves the real end-user IP: that is personal data (CJEU *Breyer*, C-582/14). See [#385](https://github.com/ArboreTeam/Arbore/issues/385) |
| **`/health` skipped** | no line emitted | The Docker healthcheck accounted for **95%** of the log (233 lines out of 244, measured 2026-09-02) and drowned out usable traffic. See [#388](https://github.com/ArboreTeam/Arbore/issues/388) |

The **full** IP is still used by the rate limiter, but only **in memory**, in a counter purged when its window expires (`WindowLimiter.purgeExpired`): none of it is persisted. The rate limiter is the active defence, not the log.

For an investigation requiring the full IP, the source is **Cloudflare**, which retains it at the edge.

### Rotation

`docker-compose.yml` sets `max-size: 10m` / `max-file: 3` on all three services. Without it, the `json-file` driver grows unbounded: logs only disappeared when a container was recreated, which is not a retention policy (GDPR art. 5(1)(e)).

At the observed rate (~500 KB/day for the backend), 30 MB is roughly **two months** — and since `/health` was excluded, those 30 MB hold only traffic with analytical value.

### Where to look for what

| Need | Today |
|---|---|
| Crash / panic | `sudo docker logs arbore-backend` — **rotation window only** |
| 5xx error | same |
| Traffic, rate-limiter 429s | access log, truncated IP |
| Deployed commit | `curl localhost:8080/health` → `commit` field ([#341](https://github.com/ArboreTeam/Arbore/issues/341)) |
| Full IP for an incident | Cloudflare logs |

## What real events found

Sentry did not merely confirm the instrumentation worked. Every defect listed
here was found by a real event, not by a code review.

| Sentry issue | build | what it found |
|---|---|---|
| `ARBORE-FRONTEND-1` | 29 | `device_app_hash`, a stable install identifier, was still shipping despite the anonymous regime (#496) |
| `ARBORE-FRONTEND-5` | 31 | fake "App Hanging" events emitted by the test suite, the XCTest harness going undetected (#506) |
| `ARBORE-FRONTEND-6` to `-9` | 31 | manual controls proving no scrubbing rule can reach `user.geo` (#498) |
| `ARBORE-FRONTEND-A` | 32 | 2 s freeze while browsing the catalogue: PNG decoding on the main thread (#518) |

Two lessons that reach beyond these cases.

**A review does not see what is outside the field it is looking at.**
`device_app_hash` does not live in `user` but in the `app` context: nobody
spotted it while reviewing the anonymisation code, and the public privacy policy
claimed the opposite for a day.

**A stack with no application frame is not a useless stack.** The one in
`ARBORE-FRONTEND-A` stopped inside the SwiftUI graph, without a single line of
our code. It still pointed at the exact place: the main thread was blocked in
rendering, so the culprit was work done at draw time rather than at call time.

## Notes / follow-ups

- The breadcrumbs bridge from the iOS app's `AppLog` (nav / AR session / garden save) is a nice-to-have, not wired up yet.
- The backend has been instrumented since #388. The **AiGenerator** (`sentry-python`) remains unwired: its errors still do not survive Docker log rotation.
- Deliberate partial coverage on 5xx: a handler returning 500 produces a synthetic event (route + status) for lack of a declared error — the code counts 40 such responses against 2 `c.Error(...)` calls. Enriching this requires handlers to declare their errors, which is a deeper change.
- Session Replay is a paid feature — not used.
