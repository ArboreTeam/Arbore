# Observability (Sentry)

Crash and performance reporting for Arbore. **iOS**, **web** and the **Go/Gin backend** are wired up; the Python AiGenerator remains in **Phase 2**.

- Issue: #205
- iOS SDK: [`sentry-cocoa`](https://github.com/getsentry/sentry-cocoa) via Swift Package Manager
- Web SDK: [`@sentry/nextjs`](https://github.com/getsentry/sentry-javascript)
- Org: `epi-apps` (sentry.io, **EU** data residency)
- Projects: `arbore-frontend` (iOS), `frontend-web-arbore` (web), `arbore-backend` (Gin)
- Backend SDK: [`sentry-go`](https://github.com/getsentry/sentry-go) + `sentrygin`

---

## Measured state — 2026-09-08

Read from the Sentry organization, not inferred from configuration. Re-measure
rather than trust: these figures age.

| project | SDK | traffic over 90 days |
|---|---|---|
| `arbore-frontend` (iOS) | ✅ | **nothing at all** |
| `frontend-web-arbore` | ✅ | 192,800 spans, 0 errors |
| `arbore-backend` | ❌ absent from `go.mod` | empty |

**Zero errors across all three projects.** That is not a sign of health, it is
the measurement of what is not wired up — see the two sections below.

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
| dSYM upload | `fastlane/Fastfile` → `beta` lane |

`SentryManager` is **disabled until a DSN is configured _and_ the user has explicitly opted in** to diagnostics sharing (the `privacy_shareData` toggle in the privacy settings, **off by default** — GDPR opt-in, #226). Without secrets or consent, the app builds and runs identically (handy for contributors and CI). `start()` is a no-op until consent is given; toggling consent starts/stops the SDK at runtime via `updateConsent(granted:uid:)`. The user context is the **Firebase UID only** (no email or name) and tracks auth state through a single `addStateDidChangeListener` in `AppDelegate`.

Options set: `environment` (`debug` / `production`, see the next section), `releaseName = version+build`, `dist = build`, `tracesSampleRate = 0.1`, `attachScreenshot = false` (privacy), `attachViewHierarchy = true`, `sendDefaultPii = false`, plus a `beforeSend` hook that strips IP / email / name / request body from every event (keeping only the UID pseudonym).

> ⚠️ **Consequence worth knowing: iOS reports nothing.** Zero events in 90 days
> (measured 2026-09-08). The mechanism works — it is consent that is never
> given, because it is never offered. The whole chain, DSN and dSYM upload
> included, is in place and has no effect. A launch crash on a tester's device
> is today indistinguishable from a tester who does not open the app. Open
> decision in #469.

### iOS setup (one-shot)

**1. DSN → `Secrets.xcconfig`.** The DSN is a `https://<publicKey>@<host>/<projectID>` URL. Since an xcconfig file treats `//` as a comment, it is stored as **three fields** reassembled in `AppConfig.sentryDSN`:

```
# Secrets.xcconfig (gitignored — never commit)
SENTRY_DSN_PUBLIC_KEY = <public key>
SENTRY_DSN_HOST       = o<org>.ingest.de.sentry.io   # .de = EU
SENTRY_DSN_PROJECT_ID = <project id>
```

Leave empty to keep Sentry disabled.

**2. dSYM symbolication (fastlane).** The `beta` lane uploads the dSYMs after the TestFlight upload. Org/project are already wired in the Fastfile (`epi-apps` / `arbore-frontend`); all that remains is to provide an auth token. Without a token, the lane logs a skip and continues.

```bash
brew install getsentry/tools/sentry-cli
cp .sentryclirc.example .sentryclirc   # then paste the token (gitignored)
bundle exec fastlane beta
```

Create the token at `sentry.io → Settings → Auth Tokens` (scopes `project:releases` + `project:write`). Instead of `.sentryclirc`, export `SENTRY_AUTH_TOKEN`; override `SENTRY_ORG` / `SENTRY_PROJECT` via the environment if needed.

### Verify (iOS)

1. Fill in the DSN in `Secrets.xcconfig`, run a **Debug** build.
2. Profile → **Debug Tools → "Send Sentry test event"** (visible in DEBUG only).
3. The event shows up in `sentry.io → arbore-frontend → Issues` within seconds, tagged `environment: debug` and with the Firebase UID.
4. For symbolicated **release** crashes, ship a `fastlane beta` build with the token above, then trigger a crash on the TestFlight build.

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

No effect today, iOS reporting nothing (see above), but it is a trap armed for
the day it does.

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

## Notes / follow-ups

- The breadcrumbs bridge from the iOS app's `AppLog` (nav / AR session / garden save) is a nice-to-have, not wired up yet.
- The backend has been instrumented since #388. The **AiGenerator** (`sentry-python`) remains unwired: its errors still do not survive Docker log rotation.
- Deliberate partial coverage on 5xx: a handler returning 500 produces a synthetic event (route + status) for lack of a declared error — the code counts 40 such responses against 2 `c.Error(...)` calls. Enriching this requires handlers to declare their errors, which is a deeper change.
- Session Replay is a paid feature — not used.
