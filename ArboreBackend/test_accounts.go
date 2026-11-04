package main

// test_accounts.go — provisionner un compte de test à email vérifié. (#725)
//
// ## Le problème
//
// Depuis #377, une adresse non vérifiée est refusée sur toute route
// authentifiée sauf `POST /users` et `DELETE /users`. Les suites
// d'intégration iOS créent des comptes jetables qu'aucune boîte mail ne peut
// valider : dix tests sur vingt-sept échouaient en `EMAIL_NOT_VERIFIED` le
// jour où ils ont enfin tourné, le 2026-11-03.
//
// ## Ce que cette route n'est PAS
//
// Pas une dérogation au portillon. Elle pose `emailVerified` sur l'identité
// Firebase ; le jeton émis ensuite porte réellement `email_verified: true` et
// le contrôle s'applique normalement. On ne contourne pas la règle, on
// provisionne un compte qui la respecte.
//
// L'option écartée était une dérogation conditionnée à la clé d'API de test.
// Relevé le 2026-11-03 : `ARBORE_API_KEY_TEST` est présente sur le backend de
// PRODUCTION. Cette dérogation y aurait donc vécu, et quiconque détient la
// clé — elle est dans la CI et sur les machines de développement — aurait pu
// agir sans adresse vérifiée. Le portillon aurait cessé d'être éprouvé par
// qui que ce soit.
//
// ## Les trois gardes, dont aucune n'est optionnelle
//
//  1. La route vit sous `/internal`, qui exige la clé d'API ET la clé
//     interne, et rend 503 quand la seconde est absente. Elle l'est en
//     production, par construction (#696) : la surface n'y existe pas.
//  2. L'adresse doit appartenir à `@arbore.test`. `.test` est un TLD réservé
//     par la RFC 2606 : il ne peut recevoir aucun courriel, donc il ne
//     désigne jamais une personne réelle.
//  3. Le compte doit déjà exister. La route ne crée rien — elle ne peut donc
//     pas servir à fabriquer une identité, seulement à marquer une identité
//     que l'appelant a déjà créée et dont il détient le mot de passe.

import (
	"net/http"
	"strings"

	"ArboreBackend/middleware"

	"github.com/gin-gonic/gin"
)

// domaineDesComptesDeTest borne la route aux adresses qui ne peuvent
// appartenir à personne. RFC 2606 réserve `.test` et garantit qu'il n'est pas
// résoluble : aucune boîte mail ne peut exister derrière.
const domaineDesComptesDeTest = "@arbore.test"

type verifierCompteDeTestPayload struct {
	Email string `json:"email" binding:"required"`
}

// estUneAdresseDeTest n'accepte que le domaine réservé, en ignorant la casse.
//
// Extrait du handler pour être testable sans Firebase : c'est la garde dont
// la rupture serait la plus coûteuse, et elle ne doit pas dépendre d'un SDK
// pour être vérifiée.
func estUneAdresseDeTest(email string) bool {
	return strings.HasSuffix(strings.ToLower(strings.TrimSpace(email)),
		domaineDesComptesDeTest)
}

// verifierCompteDeTest marque l'adresse d'un compte de test comme vérifiée.
func verifierCompteDeTest(c *gin.Context) {
	var payload verifierCompteDeTestPayload
	if err := c.ShouldBindJSON(&payload); err != nil {
		respondInvalidBody(c, err)
		return
	}

	email := strings.TrimSpace(payload.Email)
	if !estUneAdresseDeTest(email) {
		// 403 et non 400 : la demande est bien formée, c'est la cible qui est
		// refusée. Le message nomme la règle plutôt que l'adresse, pour ne pas
		// recopier dans les journaux une donnée personnelle si quelqu'un se
		// trompe de route.
		c.JSON(http.StatusForbidden, gin.H{
			"error": "Only " + domaineDesComptesDeTest + " accounts can be marked verified",
			"code":  "NOT_A_TEST_ACCOUNT",
		})
		return
	}

	uid, err := middleware.LookupUIDByEmail(c.Request.Context(), email)
	if err != nil {
		// 404 sur une identité absente : la route marque, elle ne crée pas.
		c.JSON(http.StatusNotFound, gin.H{
			"error": "Test account not found",
			"code":  "TEST_ACCOUNT_NOT_FOUND",
		})
		return
	}

	if err := middleware.MarkEmailVerified(c.Request.Context(), uid); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Could not mark the test account verified",
			"code":  "VERIFY_FAILED",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{"uid": uid, "emailVerified": true})
}
