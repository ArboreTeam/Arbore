# Observability (Sentry)

Crash and performance reporting for Arbore. **iOS** and **web** are wired up; the Go/Gin backend and the Python AiGenerator are in **Phase 2** (separate issues).

- Issue: #205
- iOS SDK: [`sentry-cocoa`](https://github.com/getsentry/sentry-cocoa) via Swift Package Manager
- Web SDK: [`@sentry/nextjs`](https://github.com/getsentry/sentry-javascript)
- Org: `epi-apps` (sentry.io, **EU** data residency)
- Projects: `arbore-frontend` (iOS), `arbore-backend` (Gin — Phase 2)

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

Options set: `environment` (`debug`/`beta`), `releaseName = version+build`, `dist = build`, `tracesSampleRate = 0.1`, `attachScreenshot = false` (privacy), `attachViewHierarchy = true`, `sendDefaultPii = false`, plus a `beforeSend` hook that strips IP / email / name / request body from every event (keeping only the UID pseudonym).

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

## Web (Next.js)

`@sentry/nextjs` is wired through three configs that **no-op without a DSN** (privacy first: `sendDefaultPii: false`, no Session Replay):

| File | Runtime | DSN |
|---|---|---|
| `web/sentry.client.config.ts` | browser | `NEXT_PUBLIC_SENTRY_DSN` |
| `web/sentry.server.config.ts` | Node server | `SENTRY_DSN` \|\| `NEXT_PUBLIC_SENTRY_DSN` |
| `web/sentry.edge.config.ts` | edge | same as server |

`web/instrumentation.ts` loads the server/edge configs based on `NEXT_RUNTIME`. `tracesSampleRate = 0.1`. The error boundaries `web/app/error.tsx` and `web/app/global-error.tsx` call `Sentry.captureException`. Source map upload is opt-in via `SENTRY_ORG` / `SENTRY_PROJECT` / `SENTRY_AUTH_TOKEN` (uncommitted); when absent, the build does not fail.

## Notes / follow-ups

- The breadcrumbs bridge from the iOS app's `AppLog` (nav / AR session / garden save) is a nice-to-have, not wired up yet.
- Backend (`sentry-go` + `sentrygin`) and AiGenerator (`sentry-python`) are in **Phase 2**; the `arbore-backend` Sentry project already exists.
- Session Replay is a paid feature — not used.
