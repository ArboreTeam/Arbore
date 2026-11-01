package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

// internal_key_test.go — issue #696.
//
// La propriété qui compte n'est pas « la bonne clé passe » : c'est « rien ne
// passe quand la clé n'est pas configurée ». Un secret non renseigné doit
// fermer la porte. La comparaison naïve
// `subtle.ConstantTimeCompare(fourni, configuré)` la laisserait grande ouverte
// dès que les deux valent "" — un en-tête vide égalerait une clé vide.

const cleInterneDeTest = "clef-interne-de-test"

// routeurDeTest monte le middleware seul derrière une route qui répond 200.
// Atteindre ce 200 est donc la preuve, et la seule, que le middleware a laissé
// passer.
func routeurDeTest(cle string) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/sonde", InternalKeyMiddleware(cle), func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"atteint": true})
	})
	return r
}

func appeler(r *gin.Engine, entete string, poser bool) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/sonde", nil)
	if poser {
		req.Header.Set(HeaderInternalKey, entete)
	}
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

func codeDe(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var corps map[string]any
	assert.NoError(t, json.Unmarshal(rec.Body.Bytes(), &corps))
	code, _ := corps["code"].(string)
	return code
}

// LE test de ce fichier. Clé non configurée : aucun en-tête, quel qu'il soit,
// ne doit ouvrir la route — surtout pas l'en-tête vide, qui est précisément
// celui qu'une comparaison à temps constant jugerait égal à "".
func TestCleInterneAbsenteRefuseToutAppel(t *testing.T) {
	r := routeurDeTest("")

	for _, cas := range []struct {
		nom    string
		entete string
		poser  bool
	}{
		{"aucun en-tête", "", false},
		{"en-tête vide — le piège de l'égalité \"\" == \"\"", "", true},
		{"en-tête quelconque", "n-importe-quoi", true},
	} {
		t.Run(cas.nom, func(t *testing.T) {
			rec := appeler(r, cas.entete, cas.poser)
			assert.Equal(t, http.StatusServiceUnavailable, rec.Code,
				"clé interne non configurée : la route doit refuser, jamais s'ouvrir")
			assert.Equal(t, "INTERNAL_ROUTES_DISABLED", codeDe(t, rec))
		})
	}
}

func TestCleInterneManquanteEstRefusee(t *testing.T) {
	rec := appeler(routeurDeTest(cleInterneDeTest), "", false)

	assert.Equal(t, http.StatusUnauthorized, rec.Code)
	assert.Equal(t, "MISSING_INTERNAL_KEY", codeDe(t, rec),
		"un code distinct de INVALID_INTERNAL_KEY : « je n'ai rien envoyé » et "+
			"« j'ai envoyé la mauvaise valeur » sont deux pannes différentes à diagnostiquer")
}

func TestCleInterneErroneeEstRefusee(t *testing.T) {
	for _, mauvaise := range []string{
		"mauvaise-clef",
		cleInterneDeTest + "x",                     // préfixe correct
		cleInterneDeTest[:len(cleInterneDeTest)-1], // presque, tronquée
		" " + cleInterneDeTest,                     // espace en tête
	} {
		rec := appeler(routeurDeTest(cleInterneDeTest), mauvaise, true)

		assert.Equal(t, http.StatusUnauthorized, rec.Code,
			"clé refusée attendue pour %q", mauvaise)
		assert.Equal(t, "INVALID_INTERNAL_KEY", codeDe(t, rec))
	}
}

func TestCleInterneValidePasse(t *testing.T) {
	rec := appeler(routeurDeTest(cleInterneDeTest), cleInterneDeTest, true)

	assert.Equal(t, http.StatusOK, rec.Code)
	assert.Contains(t, rec.Body.String(), "atteint")
}

// La clé est figée à la construction du routeur, et non relue à chaque requête.
// Donc muter l'environnement après coup ne doit rien changer : le middleware ne
// lit pas l'environnement du tout, et ce test le fixe pour qu'une « commodité »
// future ne réintroduise pas un os.Getenv par requête.
func TestCleInterneNeRelitPasLEnvironnement(t *testing.T) {
	r := routeurDeTest("")
	t.Setenv("ARBORE_INTERNAL_KEY", cleInterneDeTest)

	rec := appeler(r, cleInterneDeTest, true)

	assert.Equal(t, http.StatusServiceUnavailable, rec.Code,
		"le routeur construit sans clé doit rester fermé, même si l'environnement change ensuite")
}
