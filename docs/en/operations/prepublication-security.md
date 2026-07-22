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
