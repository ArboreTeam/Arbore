package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"ArboreBackend/middleware"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

// roles_test.go — issue #377.
//
// Verrouille les deux propriétés qui empêchent une escalade de privilège :
//   1. `role` et `tier` sont semés à la création et ne sont JAMAIS dans `$set`
//   2. le binding client de `POST /users` ne porte pas ces champs

func TestBuildCreateUserUpdateSeedsDefaultRoleAndTierOnInsertOnly(t *testing.T) {
	update := buildCreateUserUpdate("user@example.com", "Alice", false, time.Now().UTC())

	insert := operatorOf(t, update, "$setOnInsert")
	assert.Equal(t, middleware.RoleMember, insert["role"],
		"un compte neuf doit démarrer en member")
	assert.Equal(t, middleware.TierFree, insert["tier"],
		"un compte neuf doit démarrer en free")

	// Le point critique : si `role` ou `tier` passaient dans `$set`, un second
	// POST /users rétrograderait un administrateur ou réinitialiserait
	// l'abonnement d'un compte existant.
	set := operatorOf(t, update, "$set")
	assert.NotContains(t, set, "role",
		"$set ne doit jamais réécrire le rôle : un admin serait rétrogradé au prochain POST /users")
	assert.NotContains(t, set, "tier",
		"$set ne doit jamais réécrire le tier : un abonné perdrait son abonnement")
	assert.NotContains(t, set, "tierSource")
	assert.NotContains(t, set, "tierExpiresAt")
}

// hostileCreateUserBody est ce qu'un attaquant enverrait à POST /users pour
// tenter de se promouvoir administrateur ou abonné.
const hostileCreateUserBody = `{
	"name": "Mallory",
	"uid": "someone-elses-uid",
	"email": "attacker@example.com",
	"role": "admin",
	"tier": "premium",
	"tierSource": "grant",
	"banned": false
}`

// Ce test appelle la fonction de binding RÉELLEMENT utilisée par createUser, et
// non une réplique de son type : si quelqu'un réintroduit un bind sur la
// structure `User` entière, ce test échoue au lieu de rester vert.
func TestBindCreateUserPayloadIgnoresPrivilegeFields(t *testing.T) {
	gin.SetMode(gin.TestMode)
	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Request = httptest.NewRequest(http.MethodPost, "/users",
		strings.NewReader(hostileCreateUserBody))
	c.Request.Header.Set("Content-Type", "application/json")

	payload, err := bindCreateUserPayload(c)

	assert.NoError(t, err,
		"les champs inconnus doivent être ignorés, pas rejetés : les clients iOS et web envoient email/createdAt/banned")
	assert.Equal(t, "Mallory", payload.Name)

	// La surface d'écriture est exactement d'un champ. Ajouter un champ à ce
	// type sans y réfléchir fera échouer cette assertion.
	assert.Equal(t, 1, reflect.TypeOf(payload).NumField(),
		"createUserPayload ne doit exposer que `name` : tout champ supplémentaire est une surface d'écriture offerte au client")
}

// La preuve par l'absurde, qui justifie l'existence du type dédié : lier la
// structure User entière laisserait entrer les champs d'autorisation.
func TestBindingFullUserStructWouldAllowEscalation(t *testing.T) {
	var full User
	assert.NoError(t, json.Unmarshal([]byte(hostileCreateUserBody), &full))

	assert.Equal(t, "admin", full.Role)
	assert.Equal(t, "premium", full.Tier)
	assert.Equal(t, "someone-elses-uid", full.UID,
		"c'est précisément pourquoi createUser ne lie plus la structure User")
}

// Un document antérieur à #377 n'a ni `role` ni `tier`. Sa relecture doit
// produire un profil member/free, ce qui rend tout script de backfill inutile.
func TestLegacyUserDocumentNormalizesToMemberFree(t *testing.T) {
	var legacy User
	assert.NoError(t, json.Unmarshal([]byte(`{
		"uid": "legacy-uid",
		"email": "legacy@example.com",
		"name": "Bob",
		"banned": false
	}`), &legacy))

	assert.Equal(t, "", legacy.Role, "le document legacy n'a pas de rôle")
	assert.Equal(t, middleware.RoleMember, middleware.NormalizeRole(legacy.Role))
	assert.Equal(t, middleware.TierFree,
		middleware.NormalizeTier(legacy.Tier, legacy.TierExpiresAt, time.Now()))
}

// Un compte banni reste bloqué quel que soit son rôle : `banned` est un axe
// indépendant, pas une valeur de l'enum des rôles.
func TestBannedIsIndependentOfRole(t *testing.T) {
	for _, role := range []string{middleware.RoleMember, middleware.RoleAdmin, middleware.RoleOwner} {
		profile := middleware.AccessProfile{Role: role, Tier: middleware.TierFree, Banned: true}
		assert.True(t, profile.Banned,
			"le bannissement de %s ne doit pas être effacé par son rôle", role)
	}
}

// ─── #381 — resolveAccessProfile ────────────────────────────────────────────
//
// Cette fonction est sur le chemin de CHAQUE requête authentifiée. Elle était
// jusqu'ici soudée à l'appel Mongo, donc non couverte.

// Cas nominal de POST /users : le document n'existe pas encore, ce n'est pas une
// erreur et le profil par défaut doit être member/free non banni.
func TestResolveAccessProfileMissingUserIsNotAnError(t *testing.T) {
	profile, err := resolveAccessProfile(
		func(string) (User, error) { return User{}, mongo.ErrNoDocuments },
		"inconnu", time.Now(),
	)

	assert.NoError(t, err, "un utilisateur absent est le cas nominal de POST /users")
	assert.Equal(t, middleware.RoleMember, profile.Role)
	assert.Equal(t, middleware.TierFree, profile.Tier)
	assert.False(t, profile.Banned)
}

// Fail-closed : toute autre erreur de lecture remonte, pour que le middleware
// réponde 500 au lieu d'accorder un profil par défaut sur panne de base.
func TestResolveAccessProfilePropagatesReadErrors(t *testing.T) {
	boom := errors.New("connexion mongo perdue")

	profile, err := resolveAccessProfile(
		func(string) (User, error) { return User{}, boom },
		"uid", time.Now(),
	)

	assert.ErrorIs(t, err, boom, "une panne de base ne doit jamais donner un profil par défaut")
	assert.Equal(t, middleware.AccessProfile{}, profile)
}

func TestResolveAccessProfileNormalizesAndCarriesBan(t *testing.T) {
	now := time.Date(2026, 9, 2, 12, 0, 0, 0, time.UTC)
	expired := now.Add(-time.Hour)
	valid := now.Add(time.Hour)

	cases := []struct {
		name       string
		user       User
		wantRole   string
		wantTier   string
		wantBanned bool
	}{
		{
			name:     "document legacy sans role ni tier",
			user:     User{UID: "u"},
			wantRole: middleware.RoleMember, wantTier: middleware.TierFree,
		},
		{
			name:     "role inconnu replie sur member, jamais admin",
			user:     User{Role: "superuser"},
			wantRole: middleware.RoleMember, wantTier: middleware.TierFree,
		},
		{
			name:     "admin reconnu",
			user:     User{Role: "admin"},
			wantRole: middleware.RoleAdmin, wantTier: middleware.TierFree,
		},
		{
			name:     "premium encore valide",
			user:     User{Tier: "premium", TierExpiresAt: &valid},
			wantRole: middleware.RoleMember, wantTier: middleware.TierPremium,
		},
		{
			name:     "premium expiré retombe en free a la lecture",
			user:     User{Tier: "premium", TierExpiresAt: &expired},
			wantRole: middleware.RoleMember, wantTier: middleware.TierFree,
		},
		{
			name:     "banni, quel que soit le role",
			user:     User{Role: "admin", Banned: true},
			wantRole: middleware.RoleAdmin, wantTier: middleware.TierFree, wantBanned: true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			user := tc.user
			profile, err := resolveAccessProfile(
				func(string) (User, error) { return user, nil },
				"uid", now,
			)
			assert.NoError(t, err)
			assert.Equal(t, tc.wantRole, profile.Role)
			assert.Equal(t, tc.wantTier, profile.Tier)
			assert.Equal(t, tc.wantBanned, profile.Banned)
		})
	}
}

// Les tags bson doivent correspondre aux noms de champs réellement stockés.
// Un tag erroné ne casserait aucune compilation : le champ décoderait
// silencieusement à vide, donc tout le monde retomberait en member/free.
func TestUserAuthorizationFieldsSurviveBSONRoundTrip(t *testing.T) {
	expires := time.Date(2027, 1, 1, 0, 0, 0, 0, time.UTC)
	original := User{
		UID: "uid-1", Email: "a@b.c", Banned: true,
		Role: "admin", Tier: "premium",
		TierSource: "appstore", TierExpiresAt: &expires,
	}

	raw, err := bson.Marshal(original)
	assert.NoError(t, err)

	var asMap bson.M
	assert.NoError(t, bson.Unmarshal(raw, &asMap))
	for _, field := range []string{"role", "tier", "tierSource", "tierExpiresAt", "banned"} {
		assert.Contains(t, asMap, field, "le champ %s doit être stocké sous ce nom exact", field)
	}

	var decoded User
	assert.NoError(t, bson.Unmarshal(raw, &decoded))
	assert.Equal(t, "admin", decoded.Role)
	assert.Equal(t, "premium", decoded.Tier)
	assert.Equal(t, "appstore", decoded.TierSource)
	assert.True(t, decoded.Banned)
	if assert.NotNil(t, decoded.TierExpiresAt) {
		assert.True(t, expires.Equal(*decoded.TierExpiresAt))
	}
}

// ─── #381 — inventaire des routes et leur classement ────────────────────────

// Les trois classes d'accès, telles que `buildRouter` est censé les câbler.
//
// Ce que ce test protège : rien ne garantissait qu'une route ajoutée plus tard
// atterrisse sur le groupe `account` plutôt que sur `protected`. Toute nouvelle
// route fait désormais échouer ce test, ce qui force son auteur à la classer
// explicitement ici plutôt qu'à l'ouvrir aux invités par inadvertance.
//
// Limite assumée : Gin n'expose pas la chaîne de handlers d'une route, donc ce
// test vérifie l'INVENTAIRE et son classement déclaré, pas l'attachement effectif
// du garde. Ce dernier est couvert séparément par les tests de `RequireAccount`
// et `RequireAdmin` côté middleware. Une vérification bout en bout demanderait
// un double de token Firebase (hors périmètre de #381).
var (
	// Atteignables sans compte durable : catalogue, modèles 3D, config, santé,
	// les deux proxys Gemini (sur un budget de quota réduit) — et depuis #393,
	// les jardins.
	//
	// « Sans compte » ne veut pas dire « sans authentification » : hormis
	// /health, /config et les modèles, ces routes restent derrière l'API key et
	// le middleware Firebase. Ce que la classe dit, c'est qu'une session
	// ANONYME y est admise.
	//
	// Les jardins y sont entrés avec le job de réconciliation, qui garantit le
	// sort de leurs données quand Firebase supprime un compte anonyme inactif.
	// L'export et la suppression les accompagnent nécessairement : sans eux,
	// l'invité aurait des données sur le serveur sans pouvoir y accéder
	// (Art. 15) ni les effacer (Art. 17), et sa session courante est le seul
	// moment où il peut le faire — après, plus rien ne prouve son identité.
	guestReachableRoutes = []string{
		"GET /health",
		"GET /config",
		"GET /models/:filename",
		"GET /models/thumbnails/:filename",
		"GET /plants",
		"GET /plants/:id",
		"POST /chat",
		"POST /diagnose",
		"GET /users/export",
		"DELETE /users",
		"POST /gardens",
		"GET /gardens",
		"GET /gardens/:id",
		"PUT /gardens/:id",
		"DELETE /gardens/:id",
	}

	// Fermées aux invités : tout ce qui suppose un document utilisateur, donc
	// un compte durable et synchronisable entre appareils.
	accountBoundRoutes = []string{
		"POST /users",
		"GET /users/:uid",
		"POST /users/:uid/photo",
		"GET /users/:uid/photo",
		"PATCH /users/me",
		"POST /users/me/apple-link",
		"POST /consents",
		"GET /consents",
		"GET /consents/latest",
	}

	// Réservées aux administrateurs : écriture catalogue et génération IA.
	adminOnlyRoutes = []string{
		"POST /plants",
		"POST /plants/generate",
		"POST /plants/generate-multiple",
		"POST /models/thumbnails/:plantId",
	}
)

func TestRouterExposesExactlyTheClassifiedRoutes(t *testing.T) {
	t.Setenv("ARBORE_API_KEY", "clef-de-test")

	registered := map[string]bool{}
	for _, r := range buildRouter().Routes() {
		registered[r.Method+" "+r.Path] = true
	}

	classified := map[string]bool{}
	for _, group := range [][]string{guestReachableRoutes, accountBoundRoutes, adminOnlyRoutes} {
		for _, route := range group {
			assert.False(t, classified[route], "route classée deux fois : %s", route)
			classified[route] = true
		}
	}

	for route := range classified {
		assert.True(t, registered[route],
			"route classée mais absente du routeur : %s (renommée ou supprimée ?)", route)
	}
	for route := range registered {
		assert.True(t, classified[route],
			"route enregistrée mais non classée : %s — la ranger dans guestReachableRoutes, accountBoundRoutes ou adminOnlyRoutes", route)
	}

	assert.Equal(t, len(classified), len(registered), "inventaire et classement doivent coïncider")
}

// Les jardins ont motivé la création du groupe `account`, puis l'ont quitté
// avec #393 : le job de réconciliation garantit le sort de leurs données quand
// Firebase supprime un compte anonyme inactif, ce qui levait l'objection.
//
// Le garde reste néanmoins nécessaire sur `/users` et `/consents`, avec une
// liste d'exceptions COURTE et motivée. Sans elle, il aurait suffi de retirer
// le test pour ouvrir n'importe quelle route de profil aux invités.
func TestSensitiveRoutesAreNeverGuestReachable(t *testing.T) {
	guestSet := map[string]bool{}
	for _, route := range guestReachableRoutes {
		guestSet[route] = true
	}

	for _, route := range accountBoundRoutes {
		assert.False(t, guestSet[route],
			"%s ne doit jamais figurer parmi les routes ouvertes aux invités", route)
	}
	for _, route := range adminOnlyRoutes {
		assert.False(t, guestSet[route],
			"%s est une route d'administration, jamais ouverte aux invités", route)
	}

	// Les deux seules routes sous un préfixe sensible qu'un invité peut
	// atteindre, et pourquoi. Toute autre addition fera échouer ce test.
	allowedUnderSensitivePrefix := map[string]string{
		"GET /users/export": "droit d'accès (Art. 15) : un invité détenant des jardins doit pouvoir les exporter, " +
			"et sa session courante est le seul moment où il peut le demander",
		"DELETE /users": "droit à l'effacement (Art. 17), même raison — après la session, " +
			"plus aucune identité à prouver",
	}

	for _, prefix := range []string{"/consents", "/users"} {
		for _, route := range guestReachableRoutes {
			if !strings.Contains(route, prefix) {
				continue
			}
			assert.Contains(t, allowedUnderSensitivePrefix, route,
				"%s est ouverte aux invités sans justification enregistrée : "+
					"l'ajouter à allowedUnderSensitivePrefix avec sa raison, ou la fermer", route)
		}
	}
}
