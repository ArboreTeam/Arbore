# ADR 0004 — Firebase Auth as the authentication provider

- **Status**: Accepted
- **Date**: 2026-01-20
- **Deciders**: Arbore team

## Context

The application must handle **user authentication**: signup, email/password login, Google login, password reset, email verification, and account deletion. On the backend side, every user request must be attributable to an authenticated and verified user.

Several criteria weigh on the choice of a provider:

- **Delivery speed** — the project is under an academic deadline (sprint-after-sprint deliveries).
- **Cost** — as a student team, no significant budget is available.
- **GDPR compliance** — personal data (email, name) must be processed with a sufficient level of guarantee.
- **Security** — the auth chain must withstand classic attacks (brute force, credential stuffing, session hijacking).
- **Multi-platform** — the documentation targets iOS today, and web (Next.js) tomorrow.

## Decision

The application uses **Firebase Authentication** as the sole auth provider, with two methods enabled:

- **Email + password** (with automatic sending of a verification email).
- **Google Sign-In** (via the Google SDK on iOS).

On the Go backend side, every protected request is verified by the `FirebaseAuthMiddleware` middleware, which consumes the **Firebase Admin SDK** to validate the `Bearer` JWT token and extract the `uid` from it. This `uid` becomes the functional identifier used across all Mongo collections.

The password is **never transmitted to the backend** — Firebase Auth fully handles the signup/login/reset chain.

## Consequences

### Positive

- The team maintains **no custom authentication logic**: no password hashing, no sessions, no magic-token reset handling, no OAuth flow to implement. Firebase does all of this.
- Google accounts are handled with no friction on iOS — a single Google Sign-In SDK is enough.
- The **Firebase Admin SDK** on the Go side provides fast, reliable token verification (public keys cached internally).
- The system is free up to very significant volumes (50,000 MAU on the Spark tier, far beyond the expected usage).
- Sending verification and reset emails, as well as managing verified/unverified accounts, is natively integrated.
- The same auth infrastructure will be reused for the Next.js web frontend (issues #98-#109) without duplication.

### Negative

- **Strong vendor lock-in**: if Firebase becomes paid or unavailable, migrating to another provider would require migrating all the `uid`s (which are opaque Firebase strings) and rebuilding an equivalent auth system.
- **Personal data** (email) is stored at Google. This requires explicit GDPR consent and mention of the data processor in the privacy policy.
- **Authentication logs** live in the Firebase console and are not directly integrated into our backend-side observability.
- The **verification email** sent by Firebase uses the default Firebase templates, which are not very customizable without moving to Pay-as-you-go.

### Neutral

- The decoupling between `Firebase uid` ↔ Mongo document (`users.uid`) requires application-level discipline to avoid orphan accounts (Firebase OK but Mongo missing, or vice versa). This discipline is carried by `saveUserToBackendThrowing` on the iOS side, which rolls back Firebase if `POST /users` fails (see issue #137 and ADR 0005).
- **User banning** is handled at the application level (a `banned: true` flag in Mongo, checked by the Firebase middleware via `CheckUserBannedFunc`). This approach avoids disabling the account on the Firebase side, which would prevent the user from retrieving their data via the GDPR flow.

## Alternatives considered

- **Custom auth with PostgreSQL + bcrypt** — rejected due to upfront cost (≥ 2 weeks of dev just to get an MVP) and security risk (homegrown cryptography is rarely done well the first time).
- **AWS Cognito** — comparable in features to Firebase but with a historically more complex developer experience, especially on iOS where the Firebase SDK is very mature.
- **Supabase Auth** — open-source and self-hostable, but requires managing a PostgreSQL ourselves, and the iOS documentation is less extensive than Firebase's.
- **Auth0** — solid but paid beyond 7,000 users (limited free tier).
- **Apple Sign In + custom backend** — partial: Apple Sign In only covers iCloud users, so email/password auth would still be needed for the others.

## Links

- [Firebase Auth — Documentation](https://firebase.google.com/docs/auth)
- [Firebase Admin SDK Go](https://firebase.google.com/docs/admin/setup)
- [Issue #110 — Backend does not enforce email verification of the Firebase token](https://github.com/ArboreTeam/Arbore/issues/110)
- [Issue #137 — Backend POST /users silently fails on signup → orphan Firebase user](https://github.com/ArboreTeam/Arbore/issues/137)
- ADR 0005 — Self-authz pattern (which depends on Firebase Admin)
