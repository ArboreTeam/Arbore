# Backend Tests (back)

The Go backend tests live at the package root (`ArboreBackend/*_test.go`) and in `middleware/`. They use Gin's test mode. No real MongoDB is required: depending on the case, handlers are either **re-implemented as mocked Gin routers** (authorization logic) or **called directly** through an injectable seam (AI proxies, where the network call is replaced by a fake `LLMProvider` or an `httptest.Server`). The tests stay fast and hermetic.

## Inventory

| File | Covers |
|---|---|
| `ArboreBackend/main_test.go` | The bulk of the handler tests. `setupTestRouter` mounts a router with a mock API-key middleware (`X-API-Key == test_api_key_12345`) and a mock Firebase middleware (`Bearer mock_firebase_token` → uid `test_user_123`). Groups: **Health** (`GET /health`); **Models** (`GET /models/:filename`: 401 without key/token, path traversal blocked, non-`.usdz` extension → 400, missing → 404, valid file → 200 `model/vnd.usdz+zip`); **Photo** (`POST /users/:uid/photo`: owner 200, non-owner 403, no auth 401, missing field 400); **Garden delete/update/list** (ownership: non-owner → 404 and not 403 so as not to disclose the existence of an ID); **PATCH `/users/me`** (self 200, trimmed name, > 100 → 422, invalid JSON → 400); a `BenchmarkModelsEndpoint_ValidRequest` benchmark. |
| `ArboreBackend/config_test.go` | `GET /config` (#236): `version == configVersion`, `membership.enforced == false` (no gating in beta), `wizard.gardenStyles` (6 value/label/tier entries), care schedules (`care.intervalsDays.repot == 180`). |
| `ArboreBackend/crypto_test.go` | AES-256-GCM (`encryptWith`/`decryptWith`): round-trip, the ciphertext does not contain the plaintext, wrong key → failure, tampered tag → failure, blob too short → failure. |
| `ArboreBackend/apple_revocation_test.go` | Sign in with Apple revocation: `generateClientSecret()` (ES256 JWT with kid/iss/sub/aud), `exchangeAuthorizationCode` against an `httptest` server (verified form fields, returned refresh_token, Apple error path), `revokeRefreshToken` (token + `token_type_hint=refresh_token`). The `appleTokenURL`/`appleRevokeURL` package variables are swapped to the test server. |
| `ArboreBackend/middleware/firebase_auth_test.go` | `isReleaseMode()`, `InitFirebase()` (fatal in release if the credential is missing/invalid, OK in debug), fail-closed semantics (`firebaseAuth == nil` in release → 503, in debug → passes through with uid `unauthenticated`), missing header → 401, invalid format → 401. |
| `ArboreBackend/gemini_provider_test.go` | Gemini provider translation: `buildGeminiPayload` (system/history/image, roles) and `extractGeminiText` (OK, blocked when no candidate, invalid JSON). |
| `ArboreBackend/httphardening_test.go` | **Interruptible** backoff (`backoffOrCancel`: waits the duration, or returns immediately if the context is cancelled). |
| `ArboreBackend/promptsafety_test.go` | Anti-injection helpers: `truncateRunes` (rune-safe truncation) and `sanitizeLine` (control-character removal, whitespace collapsing, truncation). |
| `ArboreBackend/ai_handlers_test.go` | The `/chat` and `/diagnose` handlers called **for real** via a fake `LLMProvider` injected: empty message → 400, markdown stripped, bounded history + anti-injection clause present, image required, JSON extraction (raw and embedded in prose), blocked, upstream errors → 502, `plantName` sanitized and framed. |
| `ArboreBackend/diagnose_normalize_test.go` | Diagnosis normalization (`normalizeDiagnose`): clamp to `[0,1]`, bounds (max diseases / recommendations), nameless diseases dropped, defaults (`isUncertain=true`, `species` null when empty), arrays never `null`, invalid JSON → error. |
| `ArboreBackend/mistral_provider_test.go` | Mistral provider translation: `buildMistralPayload` (system → history → current turn ordering, role `assistant` rather than `model`, content stays a plain string without an image, **image = data URI under a `url` key**) and `extractMistralText` (normal response, no choice = blocking, invalid JSON); missing key fails before any request, key travels in the header, a definitive error is not retried, default model and override. |
| `ArboreBackend/llm_throttle_test.go` | Throttling decorator (#553): with no declared rate the provider is **not** wrapped (and `nil` stays `nil`), with a rate it is, preserving name and limits; the rate is actually enforced; beyond the max wait → `ErrLLMSurcharge` **without calling** the provider; context cancellation during the wait; defaults and overrides for `AI_THROTTLE_MAX_WAIT` and `*_RPS`. |
| `ArboreBackend/llm_throttle_concurrency_test.go` | The same decorator **under concurrency**: ten simultaneous callers respect the global rate, which does not depend on how many callers there are; under saturation refusals stay clean. Also covers `initLLMProvider` (Gemini not throttled, Mistral throttled, empty value = Gemini, unknown name → failure) and the Mistral HTTP layer (429 and 5xx retried then succeeding, cancellation interrupting the wait between attempts, transport failure, invalid URL with no retry, truncated response); guardrails on the default model: granted family, **never a Labs model**, declared rate consistent with it. |
| `ArboreBackend/catalog_context_test.go` | Catalogue grounding (#554), pure logic: `normaliserNom` (accents, `×`, punctuation), `trouverFiche` (exact equality, name buried in a sentence, longest match wins, **no fuzzy matching**, genus alone → full name, empty catalogue), `fichesMentionnees` (several plants, bound respected, too-short names ignored, no duplicates), and `formaterFiches` (header announcing **data** rather than an instruction, diagnosis/assistant variants, toxicity derived from the flags, a name unable to open a fake section, language respected). |
| `ArboreBackend/catalog_reel_test.go` | The same grounding confronted with the **real catalogue names** (`testdata/noms_catalogue.txt`): no name normalises to empty, no normalisation collisions, user phrasings, exotic characters, extraction from a conversation, and **no false positive** on a general question. This file found two bugs the synthetic tests let through. |
| `ArboreBackend/roles_test.go` | Roles and privileges: default role/tier seeded on insert only, privilege fields in the creation payload are **ignored** (and binding the full struct would allow escalation — demonstrated), legacy document normalised to `member`/`free`, ban independent of role, `resolveAccessProfile` (missing user ≠ error, read errors propagated, normalisation + ban carried through), BSON round-trip, and two **surface** tests: the router exposes exactly the classified routes, and sensitive routes are never guest-reachable. |
| `ArboreBackend/audit338_test.go` | Hardening from audit #338: metacharacter escaping in the plant-name filter, `buildCreateUserUpdate` (preserved fields never touched, insert/update split, empty name omitted, test documents labelled on insert only), error responses leaking no internal detail, `resolveMasterEncryptionKey` (file takes precedence over env, content trimmed, fallback to the variable, unreadable file reported, ciphertexts interoperable across sources) and CORS (`parseAllowedOrigins`, disabled by default, only the configured origin allowed). |
| `ArboreBackend/secrets_test.go` | File-mounted secrets (`*_PATH`): a mounted file takes precedence, fallback to the environment with no path, an unreadable path does not mask the variable, an empty file falls back, edge whitespace stripped, no source → empty secret. |
| `ArboreBackend/httplogging_test.go` | Logging: `maskIP` keeps only the network prefix (IPv4 and IPv6) and rejects non-addresses, the formatter **never** emits a full IP, and the access log skips `/health` — and nothing else. |
| `ArboreBackend/indexes_test.go` | MongoDB indexes: the required indexes cover `uid` lookups, only `users.uid` is unique, `formatIndexKeys` preserves ordering, index failures handle both conflict codes and point to the migration on a duplicate key, and `ensureIndexes` on a `nil` database does not panic. |
| `ArboreBackend/climate_test.go` | Climate profile: location required, regional coastal estimate, nearest-station altitude when configured, low-confidence regional fallback. |
| `ArboreBackend/storageprovider_test.go` | Storage contract: path escape refused, “missing” distinguished from “failure”, round-trip, seekable `Open`, the filesystem backend has no presigning, unknown provider → failure. |
| `ArboreBackend/storage_s3_test.go` | S3 backend: key mapping, escape refused, 404 classification, incomplete configuration refused. |
| `ArboreBackend/storage_guard_test.go` | Storage rate guard: stops at the limit, resets after the window, rejects oversized payloads **before** counting them, throttles presigning, counts presigns and opens together, disabled at zero, configured from environment variables. |
| `ArboreBackend/account_cleanup_test.go` | Account cleanup: the legacy community image is deleted only inside the configured directory and only for an expected extension. |
| `ArboreBackend/reconcile_guests_test.go` | Guest reconciliation: an empty Firebase set is refused (guardrail against a full purge), the grace period never disables itself and defaults to seven days, reconciled collections match those of the purge, `community_posts` does use the `userId` field. |
| `ArboreBackend/botanical_schema_test.go` | JSON round-trip for `PlantBotanicalProfile` and `GardenCompatibilityContext` (contract shared with iOS). |

## What these tests guarantee

- **Access security**: presence/validity of the API key and the Firebase token on protected routes; rejection of path traversal on the `models` routes.
- **Ownership-based authorization (self-authz)**: a user can neither read, modify, nor delete another user's gardens / photos; responses avoid disclosing the existence of other users' resources.
- **Encryption at rest**: the Apple refresh token is protected with AES-256-GCM and resists tampering.
- **Apple compliance**: the ES256 `client_secret` generation and the token exchanges/revocations follow Apple's protocol.
- **AI proxy hardening**: per-`uid` rate limiting, body cap and interruptible backoff, bounded inputs and anti-injection clause, and diagnosis output-schema normalization (clamped values, iOS contract honored).
- **Throughput throttling towards the provider**: the free quota is respected even under concurrency, refusal is clean rather than an upstream 429, and the default model stays in the granted family — never a Labs model (see [`../operations/llm-providers.md`](../operations/llm-providers.md)).
- **Catalogue grounding**: name matching is exact and bounded to word boundaries — tested against the **real** catalogue names, not only hand-picked examples — and the reference block injected into the prompt cannot pass itself off as an instruction.
- **Log data leakage**: no full IP is ever logged.
- **Storage**: no path escape, and a rate guard bounds the cost of the object backend.

## Running

```sh
# Via Makefile
make test-backend

# Direct
cd ArboreBackend && go vet ./...
cd ArboreBackend && go test -v -race -coverprofile=coverage.out -covermode=atomic ./...
cd ArboreBackend && go tool cover -func=coverage.out

# Lint (golangci-lint v2, root config)
cd ArboreBackend && golangci-lint run --config=../.golangci.yml --timeout=5m ./...
```

In CI (`.github/workflows/ci.yml`, `backend` job): `go mod download && verify` → `go vet` → `go test -race -coverprofile` → Codecov upload (non-blocking) → `golangci-lint` → cross-build linux/amd64 + darwin/arm64. The `.golangci.yml` configuration notably enables `errcheck`, `govet`, `staticcheck`, `revive`, `gocyclo` (max complexity 24) and `gosec`.

## Known limitations

- No **blocking coverage threshold** (Codecov in publish-only mode).
- The tests use mocked routers: they validate the **authorization and format logic**, not the real MongoDB integration (covered on the iOS side by the integration tests that hit the real backend).
- `ArboreBackend/go.mod` declares `go 1.25.14`: the CI `GO_VERSION` variable must stay aligned.
