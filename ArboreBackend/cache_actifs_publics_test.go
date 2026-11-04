package main

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

// Support de test minimal : sert des octets, ne sait pas signer. C'est le
// comportement de `filesystemStorage`, celui de la production.
type supportDOctets struct {
	contenu []byte
}

func (s *supportDOctets) Name() string { return "octets" }

func (s *supportDOctets) Open(context.Context, StorageObject) (io.ReadSeekCloser, ObjectInfo, error) {
	return lecteurFermable{bytes.NewReader(s.contenu)},
		ObjectInfo{Size: int64(len(s.contenu)), ModTime: time.Unix(0, 0)}, nil
}

func (s *supportDOctets) Put(context.Context, StorageObject, []byte) error { return nil }

func (s *supportDOctets) PresignedURL(context.Context, StorageObject, time.Duration) (string, error) {
	return "", ErrNoPresign
}

type lecteurFermable struct{ *bytes.Reader }

func (lecteurFermable) Close() error { return nil }

// TestModeleAuthentifieNEstPasMisEnCachePubliquement verrouille la raison pour
// laquelle `Cache-Control` est posé dans les deux handlers publics et NON dans
// `serveStorageObject` (#737).
//
// `servePlantModel` partage ce même `serveStorageObject`, mais il n'est monté
// que sur des routes authentifiées — `protected` et `internal`. Poser l'en-tête
// au niveau commun aurait marqué `public, max-age=14400` une réponse qui exige
// une session : une invitation à la mettre en cache pour tout le monde, au bord
// comme dans les proxys intermédiaires.
func TestModeleAuthentifieNEstPasMisEnCachePubliquement(t *testing.T) {
	gin.SetMode(gin.TestMode)

	precedent := storage
	storage = &supportDOctets{contenu: []byte("usdz-factice")}
	t.Cleanup(func() { storage = precedent })

	routeur := gin.New()
	routeur.GET("/models/:filename", servePlantModel)

	enregistreur := httptest.NewRecorder()
	routeur.ServeHTTP(enregistreur, httptest.NewRequest(http.MethodGet, "/models/plante.usdz", nil))

	if enregistreur.Code != http.StatusOK {
		t.Fatalf("le modèle devrait être servi, obtenu %d", enregistreur.Code)
	}
	if entete := enregistreur.Header().Get("Cache-Control"); entete != "" {
		t.Errorf("une route authentifiée ne doit porter aucun Cache-Control, obtenu %q", entete)
	}
}

// TestCacheDesActifsPublicsRependLaValeurDejaEffective : la constante ne doit
// pas dériver de ce que Cloudflare applique déjà au bord. L'intention de #737
// est de rendre explicite un comportement existant, pas de le changer — si
// quelqu'un veut changer la durée, que ce soit un choix délibéré et non un
// effet de bord de ce commit.
func TestCacheDesActifsPublicsReprendLaValeurDejaEffective(t *testing.T) {
	const attendu = "public, max-age=14400" // 4 h, mesuré au bord le 2026-11-04
	if cacheDesActifsPublics != attendu {
		t.Errorf("cacheDesActifsPublics = %q, attendu %q — changer cette durée\n"+
			"doit être un choix assumé, pas un glissement", cacheDesActifsPublics, attendu)
	}
}
