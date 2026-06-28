# Backend Tests (back)

The Go backend tests live at the package root (`ArboreBackend/*_test.go`) and in `middleware/`. They use Gin's test mode and `github.com/stretchr/testify/assert`. No real MongoDB is required: the handlers are **re-implemented as mocked Gin routers** that mirror the real authorization logic, which keeps the tests fast and hermetic.

## Inventory

| File | Covers |
|---|---|
| `ArboreBackend/main_test.go` | The bulk of the handler tests. `setupTestRouter` mounts a router with a mock API-key middleware (`X-API-Key == test_api_key_12345`) and a mock Firebase middleware (`Bearer mock_firebase_token` → uid `test_user_123`). Groups: **Health** (`GET /health`); **Models** (`GET /models/:filename`: 401 without key/token, path traversal blocked, non-`.usdz` extension → 400, missing → 404, valid file → 200 `model/vnd.usdz+zip`); **Photo** (`POST /users/:uid/photo`: owner 200, non-owner 403, no auth 401, missing field 400); **Garden delete/update/list** (ownership: non-owner → 404 and not 403 so as not to disclose the existence of an ID); **PATCH `/users/me`** (self 200, trimmed name, > 100 → 422, invalid JSON → 400); a `BenchmarkModelsEndpoint_ValidRequest` benchmark. |
| `ArboreBackend/config_test.go` | `GET /config` (#236): `version == configVersion`, `membership.enforced == false` (no gating in beta), `wizard.gardenStyles` (6 value/label/tier entries), care schedules (`care.intervalsDays.repot == 180`). |
| `ArboreBackend/crypto_test.go` | AES-256-GCM (`encryptWith`/`decryptWith`): round-trip, the ciphertext does not contain the plaintext, wrong key → failure, tampered tag → failure, blob too short → failure. |
| `ArboreBackend/apple_revocation_test.go` | Sign in with Apple revocation: `generateClientSecret()` (ES256 JWT with kid/iss/sub/aud), `exchangeAuthorizationCode` against an `httptest` server (verified form fields, returned refresh_token, Apple error path), `revokeRefreshToken` (token + `token_type_hint=refresh_token`). The `appleTokenURL`/`appleRevokeURL` package variables are swapped to the test server. |
| `ArboreBackend/middleware/firebase_auth_test.go` | `isReleaseMode()`, `InitFirebase()` (fatal in release if the credential is missing/invalid, OK in debug), fail-closed semantics (`firebaseAuth == nil` in release → 503, in debug → passes through with uid `unauthenticated`), missing header → 401, invalid format → 401. |

## What these tests guarantee

- **Access security**: presence/validity of the API key and the Firebase token on protected routes; rejection of path traversal on the `models` routes.
- **Ownership-based authorization (self-authz)**: a user can neither read, modify, nor delete another user's gardens / photos; responses avoid disclosing the existence of other users' resources.
- **Encryption at rest**: the Apple refresh token is protected with AES-256-GCM and resists tampering.
- **Apple compliance**: the ES256 `client_secret` generation and the token exchanges/revocations follow Apple's protocol.

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
- `ArboreBackend/go.mod` declares `go 1.24.1`: the CI `GO_VERSION` variable must stay aligned.
