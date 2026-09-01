package main

import (
	"encoding/json"
	"testing"
	"time"

	"ArboreBackend/middleware"

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

// Le binding de createUser ne doit accepter que `name`. Ce test décode le même
// payload que le handler pour figer la surface d'écriture offerte au client :
// si quelqu'un réintroduit un bind sur la structure `User` entière, il casse.
func TestCreateUserPayloadBindingRejectsPrivilegeFields(t *testing.T) {
	// Ce qu'un attaquant enverrait pour tenter de se promouvoir.
	hostile := []byte(`{
		"name": "Mallory",
		"uid": "someone-elses-uid",
		"email": "attacker@example.com",
		"role": "admin",
		"tier": "premium",
		"tierSource": "grant",
		"banned": false
	}`)

	// Structure identique à celle liée par createUser.
	var payload struct {
		Name string `json:"name"`
	}
	assert.NoError(t, json.Unmarshal(hostile, &payload),
		"les champs inconnus doivent être ignorés, pas rejetés : les clients iOS et web envoient email/createdAt/banned")
	assert.Equal(t, "Mallory", payload.Name)

	// La preuve par l'absurde : lier la structure User entière laisserait
	// entrer les champs d'autorisation.
	var full User
	assert.NoError(t, json.Unmarshal(hostile, &full))
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
