# Observabilité (Sentry)

Reporting de crashs et de performance pour Arbore. **iOS** et **web** sont câblés ; le backend Go/Gin et l'AiGenerator Python sont en **Phase 2** (issues séparées).

- Issue : #205
- SDK iOS : [`sentry-cocoa`](https://github.com/getsentry/sentry-cocoa) via Swift Package Manager
- SDK web : [`@sentry/nextjs`](https://github.com/getsentry/sentry-javascript)
- Org : `epi-apps` (sentry.io, résidence des données **UE**)
- Projets : `arbore-frontend` (iOS), `arbore-backend` (Gin — Phase 2)

## iOS

| Élément | Emplacement |
|---|---|
| Wrapper SDK | `ArboreUi/ArboreUi/Observability/SentryManager.swift` |
| Init (avant Firebase) | `ArboreUi/ArboreUi/LoginAuth/AppDelegate.swift` |
| Config / assemblage DSN | `ArboreUi/ArboreUi/Config/AppConfig.swift` |
| Secrets (gitignorés) | `ArboreUi/Secrets.xcconfig` (+ `.example`) |
| Privacy manifest | `ArboreUi/ArboreUi/PrivacyInfo.xcprivacy` (CrashData + OtherDiagnosticData) |
| Upload dSYM | `fastlane/Fastfile` → lane `beta` |

`SentryManager` est **désactivé tant qu'un DSN n'est pas configuré _et_ que l'utilisateur n'a pas explicitement opté** pour le partage de diagnostics (toggle `privacy_shareData` dans les réglages de confidentialité, **off par défaut** — opt-in RGPD, #226). Sans secrets ni consentement, l'app se build et tourne à l'identique (pratique pour les contributeurs et la CI). `start()` est un no-op jusqu'au consentement ; basculer le consentement démarre/arrête le SDK à chaud via `updateConsent(granted:uid:)`. Le contexte utilisateur est l'**UID Firebase uniquement** (ni email ni nom) et suit l'état d'auth via un unique `addStateDidChangeListener` dans `AppDelegate`.

Options posées : `environment` (`debug`/`beta`), `releaseName = version+build`, `dist = build`, `tracesSampleRate = 0.1`, `attachScreenshot = false` (vie privée), `attachViewHierarchy = true`, `sendDefaultPii = false`, plus un hook `beforeSend` qui retire IP / email / nom / corps de requête de chaque événement (ne conserve que le pseudonyme UID).

### Setup iOS (one-shot)

**1. DSN → `Secrets.xcconfig`.** Le DSN est une URL `https://<publicKey>@<host>/<projectID>`. Comme un fichier xcconfig traite `//` comme un commentaire, il est stocké en **trois champs** réassemblés dans `AppConfig.sentryDSN` :

```
# Secrets.xcconfig (gitignoré — ne jamais committer)
SENTRY_DSN_PUBLIC_KEY = <public key>
SENTRY_DSN_HOST       = o<org>.ingest.de.sentry.io   # .de = UE
SENTRY_DSN_PROJECT_ID = <project id>
```

Laisser vide pour garder Sentry désactivé.

**2. Symbolication dSYM (fastlane).** La lane `beta` uploade les dSYM après l'upload TestFlight. Org/projet sont déjà câblés dans le Fastfile (`epi-apps` / `arbore-frontend`) ; il ne reste qu'à fournir un token d'auth. Sans token, la lane log un skip et continue.

```bash
brew install getsentry/tools/sentry-cli
cp .sentryclirc.example .sentryclirc   # puis coller le token (gitignoré)
bundle exec fastlane beta
```

Créer le token sur `sentry.io → Settings → Auth Tokens` (scopes `project:releases` + `project:write`). À la place de `.sentryclirc`, exporter `SENTRY_AUTH_TOKEN` ; surcharger `SENTRY_ORG` / `SENTRY_PROJECT` via l'environnement si besoin.

### Vérifier (iOS)

1. Renseigner le DSN dans `Secrets.xcconfig`, lancer un build **Debug**.
2. Profil → **Debug Tools → « Send Sentry test event »** (visible en DEBUG uniquement).
3. L'événement apparaît dans `sentry.io → arbore-frontend → Issues` en quelques secondes, tagué `environment: debug` et avec l'UID Firebase.
4. Pour des crashs **release** symbolisés, livrer un build `fastlane beta` avec le token ci-dessus, puis déclencher un crash sur le build TestFlight.

## Web (Next.js)

`@sentry/nextjs` est câblé via trois configs qui **no-op sans DSN** (vie privée d'abord : `sendDefaultPii: false`, pas de Session Replay) :

| Fichier | Runtime | DSN |
|---|---|---|
| `web/sentry.client.config.ts` | navigateur | `NEXT_PUBLIC_SENTRY_DSN` |
| `web/sentry.server.config.ts` | serveur Node | `SENTRY_DSN` \|\| `NEXT_PUBLIC_SENTRY_DSN` |
| `web/sentry.edge.config.ts` | edge | idem serveur |

`web/instrumentation.ts` charge les configs serveur/edge selon `NEXT_RUNTIME`. `tracesSampleRate = 0.1`. Les frontières d'erreur `web/app/error.tsx` et `web/app/global-error.tsx` appellent `Sentry.captureException`. L'upload des source maps est opt-in via `SENTRY_ORG` / `SENTRY_PROJECT` / `SENTRY_AUTH_TOKEN` (non committés) ; absent, le build n'échoue pas.

## Notes / suites

- Le pont breadcrumbs depuis l'`AppLog` de l'app iOS (nav / session AR / sauvegarde jardin) est un nice-to-have pas encore câblé.
- Backend (`sentry-go` + `sentrygin`) et AiGenerator (`sentry-python`) sont en **Phase 2** ; le projet Sentry `arbore-backend` existe déjà.
- Session Replay est une fonctionnalité payante — non utilisée.
