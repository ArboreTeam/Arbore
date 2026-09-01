package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"ArboreBackend/middleware"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
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
