# Observability (Sentry)

Crash + performance reporting for Arbore. Phase 1 (this doc) covers **iOS**;
the Go/Gin backend and the Python AiGenerator are Phase 2 (separate issues).

- Issue: #205
- SDK: [`sentry-cocoa`](https://github.com/getsentry/sentry-cocoa) via Swift Package Manager
- Org: `epi-apps` (sentry.io, **EU** data residency)
- Projects: `arbore-frontend` (iOS), `arbore-backend` (Gin — Phase 2)

## How it works

| Piece | Location |
|-------|----------|
| SDK wrapper | `ArboreUi/ArboreUi/Observability/SentryManager.swift` |
| Init (before Firebase) | `ArboreUi/ArboreUi/LoginAuth/AppDelegate.swift` |
| Config / DSN assembly | `ArboreUi/ArboreUi/Config/AppConfig.swift` |
| Secrets (gitignored) | `ArboreUi/Secrets.xcconfig` (+ `.example`) |
| Privacy manifest | `ArboreUi/ArboreUi/PrivacyInfo.xcprivacy` (CrashData + OtherDiagnosticData) |
| dSYM upload | `fastlane/Fastfile` → `beta` lane |

`SentryManager` is **disabled unless a DSN is configured** — without secrets the
app builds and runs exactly the same (handy for contributors and CI). The user
context is the Firebase **UID only** (no email/name) and follows the auth state
via a single `addStateDidChangeListener` in `AppDelegate`.

Options set: `environment` (`debug`/`beta`), `releaseName = version+build`,
`dist = build`, `tracesSampleRate = 0.1`, `attachScreenshot = false` (privacy),
`attachViewHierarchy = true`.

## Setup (one-shot)

### 1. DSN → `Secrets.xcconfig`

The DSN is a URL `https://<publicKey>@<host>/<projectID>`. Because `.xcconfig`
treats `//` as a comment, it is stored as **three fields** and reassembled in
`AppConfig.sentryDSN`. From the iOS project DSN
(`sentry.io → arbore-frontend → Settings → Client Keys`):

```
# Secrets.xcconfig (gitignored — never commit)
SENTRY_DSN_PUBLIC_KEY = <public key>
SENTRY_DSN_HOST       = o<org>.ingest.de.sentry.io   # .de = EU
SENTRY_DSN_PROJECT_ID = <project id>
```

Leave empty to keep Sentry off.

### 2. dSYM symbolication (fastlane)

The `beta` lane uploads dSYMs after the TestFlight upload. Org/project are
already wired in the Fastfile (`epi-apps` / `arbore-frontend`), so the **only**
thing to provide is an auth token. If no token is found it logs a skip and the
lane continues.

```bash
brew install getsentry/tools/sentry-cli
cp .sentryclirc.example .sentryclirc   # then paste the token (gitignored)
bundle exec fastlane beta
```

Create the token at `sentry.io → Settings → Auth Tokens` (scopes
`project:releases` + `project:write`). Instead of `.sentryclirc` you can export
`SENTRY_AUTH_TOKEN`; override `SENTRY_ORG` / `SENTRY_PROJECT` via env if needed.

## Verify

1. Set the DSN in `Secrets.xcconfig`, run a **Debug** build.
2. Profile → **Debug Tools → “Send Sentry test event”** (visible in DEBUG only).
3. The event appears in `sentry.io → arbore-frontend → Issues` within seconds,
   tagged with environment `debug` and your Firebase UID.
4. For symbolicated **release** crashes, ship a `fastlane beta` build with the
   env vars above, then trigger a crash on the TestFlight build.

## Notes / follow-ups

- Breadcrumb bridge from the app's `AppLog` (nav / AR session / garden save) is a
  nice-to-have not yet wired — follow-up.
- Backend (`sentry-go` + `sentrygin`) and AiGenerator (`sentry-python`) are
  Phase 2; the `arbore-backend` Sentry project already exists.
- Session Replay is a paid feature — not used.
