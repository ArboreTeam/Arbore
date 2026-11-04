# Pre-publication security

Reference state as of 22 July 2026.

## Authorization

All protected routes require an API key and a valid Firebase token. Health checks and thumbnails remain public; the public configuration endpoint requires the API key only. Operations that mutate the catalog (`POST /plants`), generate plant sheets (`POST /plants/generate` and `/plants/generate-multiple`), or upload a thumbnail additionally require the administrator role.

The role primarily comes from the Firebase `admin: true` or `role: admin` claims. `ARBORE_ADMIN_UIDS` is only a bootstrap or recovery allow-list. It must contain Firebase UIDs only and be handled as a production secret.

## Server limits

- Authenticated API: 120 requests per minute per UID.
- AI chat: 20 requests per minute and 100 per 24-hour period.
- Diagnosis: 6 requests per minute and 20 per 24-hour period.
- Administrator generation: 5 requests per minute and 50 per 24-hour period.
- Uploads: 10 requests per minute.
- JSON body: 10 MiB maximum; profile photo: 5 MiB; diagnosis image: 6 MiB; thumbnail: 8 MiB.
- Messages: 2,000 characters; chat history: 30 messages; bulk generation: 10 plants.
- HTTP server: 10 s headers, 30 s read, 120 s write, and 120 s idle timeouts.

The limiter is in memory and scoped to one instance. Before scaling horizontally, replace it with a shared quota store (for example Redis or Cloudflare rate limiting), otherwise users can multiply their quota across instances.

## Account deletion

`DELETE /users` removes gardens, consent records, the MongoDB profile, residual legacy community posts, and the Firebase identity. For an Apple account, Arbore also attempts to revoke the token before erasing the profile. On iOS, local chat history, projects, routines, notifications, and AR files are removed after server confirmation.

The route can be retried if Firebase fails after MongoDB deletions. The complete flow must still be tested with temporary email, Google, and Apple accounts before every submission.

## Deployment

1. Deploy images built from the locked versions in the repository.
2. Ensure container ports remain bound to `127.0.0.1` and are exposed only through the TLS proxy.
3. Check `0600` permissions on `.env` and its backups.
4. Ensure the Apple private key exists outside the repository and is readable only by the service.
5. Test `/health`, `401`, `403`, `413`, and `429` responses, then a complete account deletion.
6. Publish privacy policy version 2.2 before submitting the build to Apple.

---

## What has changed since — addendum of 2026-11-03

This document is a **dated snapshot**, and that is a useful format: it states
what was true on a date, not what is true today. Two facts have contradicted it
since, found while auditing the codebase. They are recorded here rather than
folded into the body, so as not to spoil the snapshot.

**Uploading a thumbnail no longer always requires the administrator role.** The
sentence "operations that … upload a thumbnail additionally require the
administrator role" still holds for `POST /models/thumbnails/:plantId`. But
#696 added `POST /internal/models/thumbnails/:plantId`, which requires **two
keys** — `X-API-Key` and `X-Arbore-Internal-Key` — and **no role**.

This is not a weakening: the internal key opens only three gestures (list the
catalogue, read a model, upload a thumbnail), grants no role, opens no account
route, and the API key alone is not enough. When absent, the routes answer 503
— production does not carry it. Detail in
[`../architecture/03-components-backend.md`](../architecture/03-components-backend.md).

**The thumbnail upload ceiling went from 10 to 200 per minute.** The line
"Uploads: 10 requests per minute" still holds for profile photos
(`uploadMinuteLimiter`). Thumbnails have their own limiter,
`vignettesParMinute = 200`, because republishing a catalogue has to go through
in one pass: at ten per minute it stopped at the tenth and took forty-nine
refusals in a row. A batch route's ceiling is measured by the size of the
batch.

The remaining values were re-checked against `main.go` on 2026-11-03 and hold:
300/min public, 120/min authenticated, 20 and 100 for chat, 6 and 20 for
diagnosis, 10 MiB JSON body, 5 MiB profile photo, 6 MiB diagnosis image, 8 MiB
thumbnail.
