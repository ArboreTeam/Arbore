package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"ArboreBackend/middleware"

	"github.com/stretchr/testify/assert"
)

// internal_routes_test.go — issue #696.
//
// Ces tests tapent sur le routeur RÉEL, celui que `main()` construit, et non
// sur une réplique de sa chaîne de middlewares. C'est la seule façon de fixer
// ce qui nous intéresse : non pas « le middleware fonctionne » (c'est l'objet
// de middleware/internal_key_test.go) mais « il est branché au bon endroit, et
// son arrivée n'a rien desserré ailleurs ».
//
// Aucun n'a besoin de Mongo ni de Firebase. Les refus coupent avant le
// handler ; le seul cas qui l'atteint y entre avec un identifiant invalide, ce
// que `uploadPlantThumbnail` rejette par un 400 avant toute requête en base.
// « Handler atteint » est donc observable sans dépendance.

const (
	cleApiDeTest      = "clef-api-de-test"
	cleInterneRouteur = "clef-interne-du-routeur"

	// Volontairement pas un ObjectID : `uploadPlantThumbnail` répond 400 dès sa
	// première ligne. Ce 400 est notre témoin « la chaîne de gardes est
	// traversée », sans Mongo.
	ficheInvalide = "pas-un-objectid"
)

func routeurReel(t *testing.T, cleInterne string) http.Handler {
	t.Helper()
	t.Setenv("ARBORE_API_KEY", cleApiDeTest)
	t.Setenv("ARBORE_INTERNAL_KEY", cleInterne)
	return buildRouter()
}

func poster(h http.Handler, chemin string, entetes map[string]string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, chemin, strings.NewReader(""))
	for k, v := range entetes {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func codeErreur(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var corps map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &corps); err != nil {
		return ""
	}
	code, _ := corps["code"].(string)
	return code
}

// Les deux secrets sont exigés ENSEMBLE. Ni l'un ni l'autre ne suffit.
func TestRouteInterneExigeLesDeuxSecrets(t *testing.T) {
	h := routeurReel(t, cleInterneRouteur)
	chemin := "/internal/models/thumbnails/" + ficheInvalide

	t.Run("sans clé d'API", func(t *testing.T) {
		rec := poster(h, chemin, map[string]string{
			middleware.HeaderInternalKey: cleInterneRouteur,
		})
		assert.Equal(t, http.StatusUnauthorized, rec.Code)
		assert.Equal(t, "MISSING_API_KEY", codeErreur(t, rec),
			"la clé interne ne remplace pas la clé d'API")
	})

	t.Run("clé d'API erronée", func(t *testing.T) {
		rec := poster(h, chemin, map[string]string{
			"X-API-Key":                  "mauvaise",
			middleware.HeaderInternalKey: cleInterneRouteur,
		})
		assert.Equal(t, http.StatusUnauthorized, rec.Code)
		assert.Equal(t, "INVALID_API_KEY", codeErreur(t, rec))
	})

	t.Run("sans clé interne", func(t *testing.T) {
		rec := poster(h, chemin, map[string]string{"X-API-Key": cleApiDeTest})
		assert.Equal(t, http.StatusUnauthorized, rec.Code)
		assert.Equal(t, "MISSING_INTERNAL_KEY", codeErreur(t, rec),
			"la clé d'API seule — celle que porte l'app iOS — ne doit pas ouvrir les routes internes")
	})

	t.Run("clé interne erronée", func(t *testing.T) {
		rec := poster(h, chemin, map[string]string{
			"X-API-Key":                  cleApiDeTest,
			middleware.HeaderInternalKey: "mauvaise",
		})
		assert.Equal(t, http.StatusUnauthorized, rec.Code)
		assert.Equal(t, "INVALID_INTERNAL_KEY", codeErreur(t, rec))
	})
}

// Avec les deux secrets, le handler est atteint SANS jeton Firebase. C'est
// toute la raison d'être de l'issue : un robot ne peut pas tenir de session.
func TestRouteInterneAtteintLeHandlerSansJetonFirebase(t *testing.T) {
	h := routeurReel(t, cleInterneRouteur)

	rec := poster(h, "/internal/models/thumbnails/"+ficheInvalide, map[string]string{
		"X-API-Key":                  cleApiDeTest,
		middleware.HeaderInternalKey: cleInterneRouteur,
	})

	assert.Equal(t, http.StatusBadRequest, rec.Code,
		"le handler doit être atteint : il répond 400 sur un identifiant de fiche invalide")
	assert.Contains(t, rec.Body.String(), "Invalid plant ID")
	assert.NotContains(t, rec.Body.String(), "MISSING_AUTH_HEADER",
		"aucun jeton Firebase ne doit être réclamé sur une route interne")
}

// LE test de non-régression. La clé interne n'achète RIEN sur la route
// d'administration : celle-ci continue d'exiger une session Firebase et le rôle
// admin. Si quelqu'un déplaçait un jour `InternalKeyMiddleware` vers un groupe
// trop large, ce test tombe.
func TestCleInterneNOuvrePasLesRoutesDAdministration(t *testing.T) {
	h := routeurReel(t, cleInterneRouteur)

	rec := poster(h, "/models/thumbnails/"+ficheInvalide, map[string]string{
		"X-API-Key":                  cleApiDeTest,
		middleware.HeaderInternalKey: cleInterneRouteur,
	})

	assert.Equal(t, http.StatusUnauthorized, rec.Code,
		"la route admin doit rester fermée à qui ne présente qu'une clé interne")
	assert.Equal(t, "MISSING_AUTH_HEADER", codeErreur(t, rec),
		"elle doit continuer de réclamer un jeton Firebase")
}

// Clé interne non provisionnée — l'état de toute instance qui ne sert pas de
// robot, prod comprise au moment de cette issue. La surface doit être fermée,
// même à qui présente une clé d'API valide.
func TestRoutesInternesFermeesSansCleProvisionnee(t *testing.T) {
	h := routeurReel(t, "")

	rec := poster(h, "/internal/models/thumbnails/"+ficheInvalide, map[string]string{
		"X-API-Key":                  cleApiDeTest,
		middleware.HeaderInternalKey: "quoi-que-ce-soit",
	})

	assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
	assert.Equal(t, "INTERNAL_ROUTES_DISABLED", codeErreur(t, rec))
}
