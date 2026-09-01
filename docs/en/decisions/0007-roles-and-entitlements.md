# ADR 0007 — Roles (RBAC) kept separate from subscription entitlements

- **Status**: Accepted
- **Date**: 2026-09-01
- **Deciders**: Arbore team

## Context

Before this decision, authorization relied on three disjoint mechanisms: the `users.banned` boolean, the `RequireAdmin()` middleware reading Firebase custom claims with a fallback on `ARBORE_ADMIN_UIDS`, and a purely informational `tier` field served by `GET /config` with `membership.enforced = false`.

Three needs converged: telling a paying user apart from a free one (a prerequisite for #4), eventually allowing guest access without account creation, and clarifying what the administrator and test-account notions actually cover.

The initial framing proposed a single enum: `invited`, `free`, `premium`, `admin`, `test`. Two findings in the code shaped the decision. First, the `ARBORE_API_KEY_TEST` key bypasses no rate limit — `rateLimitKey()` only knows `uid:` and `ip:`, and the key merely routes to the test database. Second, no code in the repository sets a Firebase custom claim, so administrators in practice come only from the bootstrap environment variable.

## Decision

**Two distinct authorization axes, never merged into a single enum.**

- `role` answers "what are you allowed to do?": `guest`, `member`, `admin`. `owner` and `support` are reserved in the enum but no route distinguishes them yet.
- `tier` answers "what have you paid for?": `free`, `premium`, alongside `tierSource` and `tierExpiresAt`.
- `banned` remains a third, independent axis, unchanged.

The `guest` role is derived from `token.Firebase.SignInProvider == "anonymous"`, never from a database field: a Mongo document is writable by its owner, a Firebase-signed claim is not.

**No `test` role is created.** The need for wider quotas during testing is handled at the environment level, through the database selector already present in the request context, rather than through an attribute carried by an account.

The access profile is read from the `FindOne` the middleware already performed for the ban check, then stored in the Gin context.

## Consequences

### Positive

- **No cartesian product.** An administrator can be a subscriber, and a guest will be able to pay, without the enum exploding.
- **No additional read cost**: the per-request `FindOne` already existed. Reading the role from the database rather than a claim also avoids the one-hour custom-claim propagation delay.
- **No backfill.** `NormalizeRole` and `NormalizeTier` fold any empty or unknown value to `member` / `free`, which covers every pre-existing document.
- **Escalation surface closed.** `POST /users` no longer binds the whole `User` struct but a payload restricted to `name`.
- **Subscription expiry is applied at read time**, without depending on an external job.

### Negative

- **Two sources to keep consistent** between MongoDB and Firebase custom claims for the administrator role. The duplication is deliberate: the claim survives a database compromise, which is defence in depth.
- **A tier change mid-quota-window** grants a fresh budget, since each class owns its counter. The error leans in favour of the customer who just paid.
- **The `guest` and `premium` values stay inert** until Anonymous Auth and StoreKit receipt validation are wired in.

### Neutral

- The default fallback is `member`, never `guest`: a degraded read must deny access to admin routes, not flip an existing account into guest access.
- The reserved `support` role is deliberately not privileged: it is read access, not administrative access.

## Alternatives considered

- **A single enum mixing role and subscription** — rejected: it produces a cartesian product as soon as a user combines both dimensions.
- **A `test` role bypassing rate limits** — rejected: a privilege carried by an account is portable and exportable. Test-account credentials circulate by nature (acceptance test plan, review board), and the bypass would apply to the routes calling Gemini, which cost money. The "key to sign in, then role bypasses" variant is strictly less safe than the status quo: it moves the privilege from the environment to the account.
- **A proprietary guest identifier** — rejected in favour of Firebase Anonymous Auth. A homegrown identifier would require an authentication path parallel to the existing middleware, hence a second surface to secure. Anonymous Auth provides a uid and a token usable without middleware changes, and allows linking the anonymous account to a named one later: a guest who signs up keeps their data.
- **Role carried solely by Firebase custom claims** — rejected: the one-hour propagation delay would make any demotion slow, whereas the database is already read on every request.

## Links

- [Issue #377 — User roles and subscription tiers](https://github.com/ArboreTeam/Arbore/issues/377)
- [Issue #4 — Payment: subscription purchase](https://github.com/ArboreTeam/Arbore/issues/4)
- [Issue #336 — Monetisation: legal and technical prerequisites](https://github.com/ArboreTeam/Arbore/issues/336)
- ADR 0004 — Firebase Auth (provides the token the `guest` role is derived from)
- ADR 0005 — Self-authz via token uid (anticipated the need for an admin role)
- [OWASP — Broken Function Level Authorization](https://owasp.org/API-Security/editions/2023/en/0xa5-broken-function-level-authorization/)
