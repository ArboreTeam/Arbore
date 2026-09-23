# Tests Backend (back)

Les tests du backend Go vivent à la racine du package (`ArboreBackend/*_test.go`) et dans `middleware/`. Ils utilisent le mode test de Gin. Aucun MongoDB réel n'est requis : selon le cas, les handlers sont **re-implémentés en routers Gin mockés** (logique d'autorisation) ou **appelés directement** via une indirection injectable (proxies IA, où l'appel réseau est remplacé par un faux `LLMProvider` ou un `httptest.Server`). Les tests restent rapides et hermétiques.

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
| `ArboreBackend/ai_handlers_test.go` | Handlers `/chat` et `/diagnose` appelés **réellement** via un faux `LLMProvider` injecté : message vide → 400, markdown nettoyé, historique borné + clause anti-injection présente, image obligatoire, extraction JSON (brut et noyé dans du texte), blocage, erreurs amont → 502, `plantName` assaini et encadré. |
| `ArboreBackend/diagnose_normalize_test.go` | Normalisation du diagnostic (`normalizeDiagnose`) : clamp `[0,1]`, bornes (max maladies / recommandations), maladies sans nom écartées, défauts (`isUncertain=true`, `species` null si vide), tableaux jamais `null`, JSON invalide → erreur. |
| `ArboreBackend/mistral_provider_test.go` | Traduction du fournisseur Mistral : `buildMistralPayload` (ordre system → historique → tour courant, rôle `assistant` et non `model`, contenu resté chaîne sans image, **image = URI de données sous une clé `url`**) et `extractMistralText` (réponse normale, absence de choix = blocage, JSON invalide) ; clé manquante → échec avant toute requête, clé transportée dans l'en-tête, erreur définitive non retentée, modèle par défaut et surcharge. |
| `ArboreBackend/llm_throttle_test.go` | Décorateur d'étranglement (#553) : sans débit déclaré le fournisseur n'est **pas** enveloppé (et `nil` reste `nil`), avec débit il l'est en conservant nom et limites ; le débit est réellement appliqué ; au-delà de l'attente max → `ErrLLMSurcharge` **sans appeler** le fournisseur ; annulation du contexte pendant l'attente ; défauts et surcharges de `AI_THROTTLE_MAX_WAIT` et `*_RPS`. |
| `ArboreBackend/llm_throttle_concurrency_test.go` | Le même décorateur **sous concurrence** : dix appelants simultanés respectent le débit global, lequel ne dépend pas du nombre d'appelants ; sous saturation les refus restent propres. Couvre aussi `initLLMProvider` (Gemini non étranglé, Mistral étranglé, valeur vide = Gemini, nom inconnu → échec) et la couche HTTP Mistral (429 et 5xx retentés puis aboutissent, annulation interrompant l'attente entre tentatives, panne de transport, URL invalide sans réessai, réponse tronquée) ; garde-fous sur le modèle par défaut : famille accordée, **jamais un modèle Labs**, débit déclaré cohérent. |
| `ArboreBackend/catalog_context_test.go` | Ancrage catalogue (#554), logique pure : `normaliserNom` (accents, `×`, ponctuation), `trouverFiche` (égalité exacte, nom noyé dans une phrase, correspondance la plus longue, **aucune correspondance approximative**, genre seul → nom complet, catalogue vide), `fichesMentionnees` (plusieurs plantes, borne respectée, noms trop courts ignorés, pas de doublon), et `formaterFiches` (en-tête annonçant une **donnée** et non une consigne, variantes diagnostic/assistant, toxicité issue des drapeaux, nom incapable d'ouvrir une fausse section, respect de la langue). |
| `ArboreBackend/catalog_reel_test.go` | Le même ancrage confronté aux **vrais noms du catalogue** (`testdata/noms_catalogue.txt`) : aucun nom ne se normalise en vide, pas de collision de normalisation, formulations d'utilisateur, caractères exotiques, relevé dans une conversation, et **pas de faux positif** sur une question générale. Ce fichier a trouvé deux bugs que les tests synthétiques laissaient passer. |
| `ArboreBackend/roles_test.go` | Rôles et privilèges : rôle/palier par défaut semés à l'insertion seulement, les champs de privilège du payload de création sont **ignorés** (et binder la struct complète permettrait l'escalade — démontré), document hérité normalisé en `member`/`free`, bannissement indépendant du rôle, `resolveAccessProfile` (utilisateur absent ≠ erreur, propagation des erreurs de lecture, normalisation + report du ban), round-trip BSON, et deux tests de **surface** : le routeur expose exactement les routes classées, les routes sensibles ne sont jamais atteignables en invité. |
| `ArboreBackend/audit338_test.go` | Durcissements de l'audit #338 : échappement des métacaractères dans le filtre de nom de plante, `buildCreateUserUpdate` (champs préservés jamais touchés, répartition insert/update, nom vide omis, marquage des documents de test à l'insertion seule), réponse d'erreur ne divulguant aucun détail interne, `resolveMasterEncryptionKey` (fichier prioritaire sur l'env, contenu trimé, repli sur la variable, fichier illisible signalé, chiffrés interopérables entre sources) et le CORS (`parseAllowedOrigins`, désactivé par défaut, n'autorise que l'origine configurée). |
| `ArboreBackend/secrets_test.go` | Lecture des secrets montés en fichier (`*_PATH`) : fichier monté prioritaire, repli sur l'environnement sans chemin, chemin illisible ne masquant pas la variable, fichier vide → repli, espaces de bord retirés, absence de source → secret vide. |
| `ArboreBackend/httplogging_test.go` | Journalisation : `maskIP` ne garde que le préfixe réseau (IPv4 et IPv6) et rejette ce qui n'est pas une adresse, le formateur n'émet **jamais** une IP complète, et le log d'accès ignore `/health` — et rien d'autre. |
| `ArboreBackend/indexes_test.go` | Index MongoDB : les index requis couvrent les recherches par `uid`, seul l'index `users.uid` est unique, `formatIndexKeys` préserve l'ordre, l'échec d'index gère les deux codes de conflit et oriente vers la migration en cas de doublon, et `ensureIndexes` sur une base `nil` ne panique pas. |
| `ArboreBackend/climate_test.go` | Profil climatique : localisation obligatoire, estimation régionale côtière, altitude de la station la plus proche quand elle est configurée, repli régional à faible confiance. |
| `ArboreBackend/storageprovider_test.go` | Contrat de stockage : refus de l'évasion de chemin, distinction « absent » / « échec », round-trip, `Open` seekable, le backend fichier n'a pas de présignature, provider inconnu → échec. |
| `ArboreBackend/storage_s3_test.go` | Backend S3 : correspondance des clés, refus de l'évasion, classification du 404, configuration incomplète refusée. |
| `ArboreBackend/storage_guard_test.go` | Garde-fou de débit du stockage : arrêt à la limite, remise à zéro après la fenêtre, rejet du surdimensionné **avant** de le compter, étranglement des présignatures, présignatures et ouvertures comptées ensemble, désactivation à zéro, configuration par variables d'environnement. |
| `ArboreBackend/account_cleanup_test.go` | Nettoyage de compte : l'image communautaire héritée n'est supprimée que dans le répertoire configuré et seulement pour une extension attendue. |
| `ArboreBackend/reconcile_guests_test.go` | Réconciliation des invités : refus d'un ensemble Firebase vide (garde-fou anti-purge totale), le délai de grâce ne se désactive jamais lui-même et vaut sept jours par défaut, les collections réconciliées correspondent à celles de la purge, `community_posts` utilise bien le champ `userId`. |
| `ArboreBackend/botanical_schema_test.go` | Round-trip JSON de `PlantBotanicalProfile` et de `GardenCompatibilityContext` (contrat partagé avec iOS). |

## Ce qui est garanti par ces tests

- **Sécurité d'accès** : présence/validité de la clé API et du token Firebase sur les routes protégées ; rejet du path traversal sur les routes `models`.
- **Autorisation par propriété (self-authz)** : un utilisateur ne peut ni lire, ni modifier, ni supprimer les jardins / photos d'un autre ; les réponses évitent de divulguer l'existence de ressources d'autrui.
- **Chiffrement au repos** : le refresh token Apple est protégé par AES-256-GCM et résiste à l'altération.
- **Conformité Apple** : la génération du `client_secret` ES256 et les échanges/révocations de token suivent le protocole Apple.
- **Durcissement des proxies IA** : rate limiting par `uid`, cap et backoff interruptible, bornes des entrées et clause anti-injection, et normalisation du schéma de sortie du diagnostic (valeurs clampées, contrat iOS respecté).
- **Étranglement du débit vers le fournisseur** : le quota gratuit est respecté même sous concurrence, le refus est propre plutôt qu'un 429 amont, et le modèle par défaut reste dans la famille à quota — jamais un modèle Labs (cf. [`../operations/fournisseurs-llm.md`](../operations/fournisseurs-llm.md)).
- **Ancrage catalogue** : la correspondance de noms est exacte et bornée aux frontières de mots — confrontée aux **vrais noms** du catalogue, pas seulement à des exemples choisis — et le bloc de référence injecté au prompt ne peut pas se faire passer pour une consigne.
- **Fuite de données dans les logs** : aucune IP complète n'est journalisée.
- **Stockage** : aucune évasion de chemin, et un garde-fou de débit borne le coût du backend objet.

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
- `ArboreBackend/go.mod` déclare `go 1.25.14` : la variable `GO_VERSION` du CI doit rester alignée.
