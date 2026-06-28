# ADR 0005 — Self-authz via token uid (no uid in the URL)

- **Status**: Accepted
- **Date**: 2026-05-10
- **Deciders**: Arbore team

## Context

When a user edits their own data (name, photo, gardens, consents), the backend must guarantee that they **only act on their own resources**. The risk to avoid: that an authenticated user A could modify user B's data by specifying B's `uid` in the request (for example via a `PATCH /users/{uid}` URL where the `uid` is a path parameter).

When designing the new `PATCH /users/me` endpoint (issue #138), two options were on the table:

1. **`PATCH /users/{uid}`** — the target `uid` comes from the URL. The handler must compare this `uid` to the `tokenUID` extracted by the middleware and return `403` if they differ.
2. **`PATCH /users/me`** — no `uid` in the URL. The handler directly uses the `uid` extracted from the token. Every request is implicitly self-only.

The codebase already inherited variant-1 endpoints (`POST /users/:uid/photo`, `GET /users/:uid/photo`), which explicitly implement the `tokenUID == uidParam` check and return `403 Forbidden` on a mismatch.

## Decision

**Every new endpoint on the current user's resources must use the `/users/me`** pattern, **`/gardens`** (with no `uid` filter in the URL), or any other path that does **not mention the `uid`** in the URL.

The `uid` is systematically extracted from the **Firebase token** by the `FirebaseAuthMiddleware` middleware and stored in the Gin context via `c.Set("uid", ...)`. Handlers read only this source.

The legacy endpoints that accept a `uid` in the URL (`/users/:uid/photo`) remain in place so as not to break existing clients, but are **no longer the target** for new features. Their consolidation (migration to `/users/me/photo`) will be tracked in a separate issue if an API redesign is planned.

The `uid` sent in a request body is **explicitly ignored** and overwritten by the `tokenUID` (see `createUser` and `createGarden` in `main.go`).

## Consequences

### Positive

- **Reduced attack surface**: a user cannot attempt to act on behalf of another, even if they manually forge an HTTP request. The request target is inherently self.
- **Handler simplicity**: no `tokenUID == uidParam` comparison, no risk of forgetting the check in a new handler.
- **Consistent pattern** with modern REST conventions (`/users/me` is the recognized idiom for "the current user").
- **Client-side readability**: iOS calls become `NetworkManager.shared.request(endpoint: "/users/me", method: .PATCH, body: ...)` without having to concatenate the `uid` into the URL.

### Negative

- **Temporary asymmetry** in the API: legacy endpoints still use `/users/:uid/photo`, which creates a visible inconsistency for a newcomer reading the code. This inconsistency is tolerated pending a future redesign.
- **Inability to act on another user** without introducing a dedicated admin endpoint. This means that in the future, if a moderation feature becomes necessary, a separate `/admin/users/:uid` route will have to be created with a different authorization (admin role verified via a custom Firebase claim).

### Neutral

- **Public read endpoints** (`GET /plants`, `GET /models/thumbnails/:filename`) are not affected by this pattern since they carry no `uid`. They remain as-is.
- **Cascading handlers** (for example `deleteUser`, which deletes gardens, then consents, then the user) also benefit from the pattern: the `uid` is read once at the top of the handler and all `bson.M{"uid": uid}` filters benefit from it.

## Concrete application

| Endpoint | Pattern | Notes |
|---|---|---|
| `PATCH /users/me` | ✅ self-authz | Introduced by #138. Template for any new endpoint. |
| `GET /users/:uid` | ⚠️ legacy | Checks `tokenUID == uidParam` then returns 403 if they differ. |
| `POST /users/:uid/photo` | ⚠️ legacy | Same. |
| `GET /users/:uid/photo` | ⚠️ legacy | Same. |
| `POST /users` | ✅ self-authz | The body's `uid` is ignored; the `tokenUID` is used. |
| `DELETE /users` | ✅ self-authz | No `uid` in the URL. |
| `GET /gardens` | ✅ self-authz | Implicit `bson.M{"uid": tokenUID}` filter. |
| `POST /gardens` | ✅ self-authz | `garden.UID = tokenUID` forced. |
| `PUT /gardens/:id` | ✅ self-authz | The `bson.M{"_id": id, "uid": tokenUID}` filter guarantees ownership. |
| `DELETE /gardens/:id` | ✅ self-authz | Same. |
| `POST /consents` | ✅ self-authz | `consent.UID = tokenUID` forced. |
| `GET /consents` | ✅ self-authz | Filtered by `uid`. |

## Alternatives considered

- **`X-User-Id` header managed by the client** — rejected because it is equivalent to putting the `uid` in the URL: trivial to forge.
- **Signed URL with a `users/{uid}` scope** — rejected because it is more complex to implement than a classic token middleware, for minimal security gain.
- **Firebase custom claims with a role** — not needed for self-authz, but will be useful for introducing an admin role if moderation becomes a need.

## Links

- [Issue #138 — PATCH /users/me](https://github.com/ArboreTeam/Arbore/issues/138)
- [Issue #110 — Backend does not enforce Firebase token email verification](https://github.com/ArboreTeam/Arbore/issues/110)
- ADR 0004 — Firebase Auth (which provides the `uid` injected into the context)
- [OWASP — Broken Object Level Authorization](https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/)
