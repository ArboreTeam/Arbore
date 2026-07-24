# Tests Backend (back)

Les tests du backend Go vivent à la racine du package (`ArboreBackend/*_test.go`) et dans `middleware/`. Ils utilisent le mode test de Gin. Aucun MongoDB réel n'est requis : selon le cas, les handlers sont **re-implémentés en routers Gin mockés** (logique d'autorisation) ou **appelés directement** via une indirection injectable (proxies Gemini, où l'appel réseau est remplacé par une fausse réponse). Les tests restent rapides et hermétiques.

## Inventaire

| Fichier | Couvre |
|---|---|
| `ArboreBackend/main_test.go` | Le gros des tests handlers. `setupTestRouter` monte un router avec un middleware API-key mock (`X-API-Key == test_api_key_12345`) et un middleware Firebase mock (`Bearer mock_firebase_token` → uid `test_user_123`). Groupes : **Health** (`GET /health`) ; **Models** (`GET /models/:filename` : 401 sans clé/token, path traversal bloqué, extension non `.usdz` → 400, inexistant → 404, fichier valide → 200 `model/vnd.usdz+zip`) ; **Photo** (`POST /users/:uid/photo` : propriétaire 200, non-propriétaire 403, sans auth 401, champ manquant 400) ; **Garden delete/update/list** (ownership : non-propriétaire → 404 et non 403 pour ne pas divulguer l'existence d'un ID) ; **PATCH `/users/me`** (self 200, nom trimé, > 100 → 422, JSON invalide → 400) ; un benchmark `BenchmarkModelsEndpoint_ValidRequest`. |
| `ArboreBackend/config_test.go` | `GET /config` (#236) : `version == configVersion`, `membership.enforced == false` (pas de gating en beta), `wizard.gardenStyles` (6 entrées value/label/tier), barèmes d'entretien (`care.intervalsDays.repot == 180`). |
| `ArboreBackend/crypto_test.go` | AES-256-GCM (`encryptWith`/`decryptWith`) : round-trip, le chiffré ne contient pas le clair, mauvaise clé → échec, tag altéré → échec, blob trop court → échec. |
| `ArboreBackend/apple_revocation_test.go` | Révocation Sign in with Apple : `generateClientSecret()` (JWT ES256 avec kid/iss/sub/aud), `exchangeAuthorizationCode` contre un `httptest` (champs de formulaire vérifiés, refresh_token retourné, chemin d'erreur Apple), `revokeRefreshToken` (token + `token_type_hint=refresh_token`). Les variables de package `appleTokenURL`/`appleRevokeURL` sont swappées vers le serveur de test. |
| `ArboreBackend/middleware/firebase_auth_test.go` | `isReleaseMode()`, `InitFirebase()` (fatal en release si credential manquant/invalide, OK en debug), sémantique fail-closed (`firebaseAuth == nil` en release → 503, en debug → passe avec uid `unauthenticated`), en-tête manquant → 401, format invalide → 401. |
| `ArboreBackend/gemini_provider_test.go` | Traduction du fournisseur Gemini : `buildGeminiPayload` (system/historique/image, rôles) et `extractGeminiText` (OK, blocage sans candidat, JSON invalide). |
| `ArboreBackend/httphardening_test.go` | Backoff **interruptible** (`backoffOrCancel` : attend la durée, ou rend la main immédiatement si le contexte est annulé). |
| `ArboreBackend/promptsafety_test.go` | Helpers anti-injection : `truncateRunes` (troncature sûre en runes) et `sanitizeLine` (retrait des caractères de contrôle, compactage des espaces, troncature). |
| `ArboreBackend/gemini_handlers_test.go` | Handlers `/chat` et `/diagnose` appelés **réellement** via un faux `LLMProvider` injecté : message vide → 400, markdown nettoyé, historique borné + clause anti-injection présente, image obligatoire, extraction JSON (brut et noyé dans du texte), blocage, erreurs amont → 502, `plantName` assaini et encadré. |
| `ArboreBackend/diagnose_normalize_test.go` | Normalisation du diagnostic (`normalizeDiagnose`) : clamp `[0,1]`, bornes (max maladies / recommandations), maladies sans nom écartées, défauts (`isUncertain=true`, `species` null si vide), tableaux jamais `null`, JSON invalide → erreur. |

## Ce qui est garanti par ces tests

- **Sécurité d'accès** : présence/validité de la clé API et du token Firebase sur les routes protégées ; rejet du path traversal sur les routes `models`.
- **Autorisation par propriété (self-authz)** : un utilisateur ne peut ni lire, ni modifier, ni supprimer les jardins / photos d'un autre ; les réponses évitent de divulguer l'existence de ressources d'autrui.
- **Chiffrement au repos** : le refresh token Apple est protégé par AES-256-GCM et résiste à l'altération.
- **Conformité Apple** : la génération du `client_secret` ES256 et les échanges/révocations de token suivent le protocole Apple.
- **Durcissement des proxies IA** : rate limiting par `uid`, cap et backoff interruptible, bornes des entrées et clause anti-injection, et normalisation du schéma de sortie du diagnostic (valeurs clampées, contrat iOS respecté).

## Exécution

```sh
# Via Makefile
make test-backend

# Direct
cd ArboreBackend && go vet ./...
cd ArboreBackend && go test -v -race -coverprofile=coverage.out -covermode=atomic ./...
cd ArboreBackend && go tool cover -func=coverage.out

# Lint (golangci-lint v2, config racine)
cd ArboreBackend && golangci-lint run --config=../.golangci.yml --timeout=5m ./...
```

En CI (`.github/workflows/ci.yml`, job `backend`) : `go mod download && verify` → `go vet` → `go test -race -coverprofile` → upload Codecov (non bloquant) → `golangci-lint` → cross-build linux/amd64 + darwin/arm64. La configuration `.golangci.yml` active notamment `errcheck`, `govet`, `staticcheck`, `revive`, `gocyclo` (complexité max 24) et `gosec`.

## Limites connues

- Pas de **seuil de couverture bloquant** (Codecov en publication seule).
- Les tests utilisent des routers mockés : ils valident la **logique d'autorisation et de format**, pas l'intégration MongoDB réelle (couverte côté iOS par les tests d'intégration qui frappent le vrai backend).
- `ArboreBackend/go.mod` déclare `go 1.24.1` : la variable `GO_VERSION` du CI doit rester alignée.
