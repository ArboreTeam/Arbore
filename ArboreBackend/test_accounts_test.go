package main

// test_accounts_test.go — les gardes de la route de provisionnement. (#725)
//
// Cette route pose `emailVerified` sur une identité Firebase. C'est une
// surface sensible : mal bornée, elle permettrait de marquer vérifiée
// l'adresse de n'importe qui. Les trois gardes qui la rendent acceptable sont
// donc testées une par une, et deux d'entre elles sans toucher à Firebase.

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"ArboreBackend/middleware"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

// --- Garde 2 : le domaine réservé ----------------------------------------

// TestSeulLeDomaineDeTestEstAccepte est la garde la plus importante de la
// route, et la seule qui la distingue d'une porte ouverte.
//
// `.test` est réservé par la RFC 2606 et n'est pas résoluble : aucune boîte
// mail ne peut exister derrière, donc l'adresse ne désigne jamais une
// personne réelle.
func TestSeulLeDomaineDeTestEstAccepte(t *testing.T) {
	acceptees := []string{
		"test.rgpd.abc@arbore.test",
		"TEST.RGPD.ABC@ARBORE.TEST",
		"  espaces@arbore.test  ",
	}
	for _, email := range acceptees {
		require.True(t, estUneAdresseDeTest(email), "doit être acceptée : %q", email)
	}

	refusees := []string{
		"quelquun@gmail.com",
		"contact@arbore.app",
		"admin@arbore.test.example.com", // le domaine n'est pas en SUFFIXE
		"arbore.test@gmail.com",         // ni au début
		"",
		"@arbore.testing",
	}
	for _, email := range refusees {
		require.False(t, estUneAdresseDeTest(email), "doit être refusée : %q", email)
	}
}

// --- Garde 1 : la clé interne, absente en production ----------------------

// TestLaRouteNExistePasSansCleInterne verrouille l'invariant de #696 : une
// clé absente FERME la porte. En production la clé n'est pas posée, donc la
// route y répond 503 — la surface n'existe pas.
func TestLaRouteNExistePasSansCleInterne(t *testing.T) {
	gin.SetMode(gin.TestMode)
	routeur := gin.New()
	groupe := routeur.Group("/internal")
	groupe.Use(middleware.InternalKeyMiddleware("")) // clé absente
	groupe.POST("/test-accounts/verify", verifierCompteDeTest)

	enregistreur := httptest.NewRecorder()
	requete := httptest.NewRequest(http.MethodPost, "/internal/test-accounts/verify",
		strings.NewReader(`{"email":"x@arbore.test"}`))
	requete.Header.Set("Content-Type", "application/json")
	routeur.ServeHTTP(enregistreur, requete)

	require.Equal(t, http.StatusServiceUnavailable, enregistreur.Code)
	require.Contains(t, enregistreur.Body.String(), "INTERNAL_ROUTES_DISABLED")
}

func routeurDeTest(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	routeur := gin.New()
	groupe := routeur.Group("/internal")
	groupe.Use(middleware.InternalKeyMiddleware("cle-interne-de-test"))
	groupe.POST("/test-accounts/verify", verifierCompteDeTest)
	return routeur
}

func appeler(t *testing.T, routeur *gin.Engine, corps string) *httptest.ResponseRecorder {
	t.Helper()
	enregistreur := httptest.NewRecorder()
	requete := httptest.NewRequest(http.MethodPost, "/internal/test-accounts/verify",
		bytes.NewBufferString(corps))
	requete.Header.Set("Content-Type", "application/json")
	requete.Header.Set(middleware.HeaderInternalKey, "cle-interne-de-test")
	routeur.ServeHTTP(enregistreur, requete)
	return enregistreur
}

// TestUneAdresseHorsDomaineEstRefuseeAvantToutAppelFirebase : le refus doit
// intervenir AVANT la moindre interrogation du SDK. Sinon une adresse réelle
// serait au moins cherchée, et le message d'erreur dirait si elle existe.
func TestUneAdresseHorsDomaineEstRefuseeAvantToutAppelFirebase(t *testing.T) {
	reponse := appeler(t, routeurDeTest(t), `{"email":"quelquun@gmail.com"}`)

	require.Equal(t, http.StatusForbidden, reponse.Code)
	require.Contains(t, reponse.Body.String(), "NOT_A_TEST_ACCOUNT")
	// Le corps ne recopie pas l'adresse : un journal garde ses traces plus
	// longtemps qu'une donnée personnelle ne devrait vivre (#385).
	require.NotContains(t, reponse.Body.String(), "quelquun@gmail.com")
}

// TestUneDemandeMalFormeeEstRefusee : pas d'email, pas d'action.
func TestUneDemandeMalFormeeEstRefusee(t *testing.T) {
	for _, corps := range []string{`{}`, `{"email":""}`, `pas du json`} {
		reponse := appeler(t, routeurDeTest(t), corps)
		require.Equal(t, http.StatusBadRequest, reponse.Code, "corps : %s", corps)
	}
}

// --- Garde 3 : la route ne CRÉE rien --------------------------------------

// TestUneIdentiteInconnueRendUn404 : sans SDK Firebase initialisé — le cas
// des tests — la recherche échoue, et la route doit le dire sans rien créer.
//
// C'est aussi ce qui prouve la troisième garde : il n'existe aucun chemin où
// la route fabrique une identité. Elle marque ce que l'appelant a déjà créé
// et dont il détient le mot de passe.
func TestUneIdentiteInconnueRendUn404(t *testing.T) {
	reponse := appeler(t, routeurDeTest(t), `{"email":"inconnu@arbore.test"}`)

	require.Equal(t, http.StatusNotFound, reponse.Code)
	require.Contains(t, reponse.Body.String(), "TEST_ACCOUNT_NOT_FOUND")
}

// TestLaRouteEstMonteeSousInternetEtPasAilleurs relit le routeur réel.
//
// Montée par mégarde sous `protected`, la route serait joignable avec une
// simple session Firebase — donc par n'importe quel utilisateur de l'app.
func TestLaRouteEstMonteeSousInternalEtPasAilleurs(t *testing.T) {
	brut, err := os.ReadFile("main.go")
	require.NoError(t, err)
	source := string(brut)

	require.Contains(t, source, `internal.POST("/test-accounts/verify", verifierCompteDeTest)`,
		"la route doit être montée sous le groupe /internal")

	for _, groupe := range []string{"protected.POST(\"/test-accounts", "account.POST(\"/test-accounts",
		"admin.POST(\"/test-accounts", "router.POST(\"/test-accounts"} {
		require.NotContains(t, source, groupe,
			"la route ne doit exister que sous /internal")
	}
}
