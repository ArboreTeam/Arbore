package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// Tests des constats 3, 4 et 5 de l'audit sécurité #338.

// MARK: - Constat 3 — injection regex dans le filtre de déduplication

func patternOf(t *testing.T, filter bson.M) string {
	t.Helper()
	inner, ok := filter["name"].(bson.M)
	if !ok {
		t.Fatalf("filtre inattendu: %#v", filter)
	}
	rx, ok := inner["$regex"].(primitive.Regex)
	if !ok {
		t.Fatalf("$regex inattendu: %#v", inner["$regex"])
	}
	return rx.Pattern
}

func TestPlantNameFilterEscapesMetacharacters(t *testing.T) {
	for _, test := range []struct {
		name  string
		input string
	}{
		{name: "backtracking catastrophique", input: "(a+)+!"},
		{name: "alternance et quantificateurs", input: "(x|y)*{1,999}"},
		{name: "ancres injectees", input: "^.*$"},
		{name: "classe de caracteres", input: "[a-z].*"},
		{name: "echappement", input: `\d+`},
	} {
		t.Run(test.name, func(t *testing.T) {
			pattern := patternOf(t, plantNameFilter(test.input))

			// Le motif doit encadrer la version ÉCHAPPÉE du nom, pas le nom brut.
			assert.Equal(t, "^"+regexp.QuoteMeta(test.input)+"$", pattern)

			// Et il doit se comporter comme une correspondance littérale : le nom
			// ne matche que lui-même, jamais une autre chaîne qu'il aurait pu
			// capturer en tant que motif.
			compiled, err := regexp.Compile(pattern)
			if err != nil {
				t.Fatalf("motif échappé non compilable: %v", err)
			}
			assert.True(t, compiled.MatchString(test.input), "le nom doit matcher littéralement")
			assert.False(t, compiled.MatchString("aaaaaaaaaaaaaaaaaaaab"),
				"un nom échappé ne doit plus se comporter comme un motif")
		})
	}
}

func TestPlantNameFilterKeepsOrdinaryNamesUsable(t *testing.T) {
	// La déduplication insensible à la casse doit continuer de fonctionner pour
	// les noms normaux — l'échappement ne doit pas changer la sémantique utile.
	pattern := patternOf(t, plantNameFilter("Acer Palmatum"))
	assert.Equal(t, "^Acer Palmatum$", pattern)

	compiled := regexp.MustCompile("(?i)" + pattern)
	assert.True(t, compiled.MatchString("acer palmatum"))
	assert.True(t, compiled.MatchString("ACER PALMATUM"))
	assert.False(t, compiled.MatchString("Acer Palmatum Nain"))
}

// MARK: - Constat 4 — clé maître lisible depuis un fichier monté

// Construite à l'exécution plutôt qu'écrite en littéral : une chaîne de 64
// caractères hex déclenche le détecteur de secrets, et l'allowlister
// affaiblirait le scanner pour un simple fixture de test.
var testHexKey = strings.Repeat("0123456789abcdef", 4)

func TestResolveMasterEncryptionKeyPrefersFileOverEnv(t *testing.T) {
	otherKey := strings.Repeat("ab", 32)

	path := filepath.Join(t.TempDir(), "master.key")
	if err := os.WriteFile(path, []byte(testHexKey+"\n"), 0o600); err != nil {
		t.Fatalf("écriture de la clé de test: %v", err)
	}

	// Les deux sources sont définies : le fichier doit gagner.
	t.Setenv("MASTER_ENCRYPTION_KEY", otherKey)
	t.Setenv("MASTER_ENCRYPTION_KEY_PATH", path)

	key, err := resolveMasterEncryptionKey()
	if err != nil {
		t.Fatalf("résolution échouée: %v", err)
	}
	expected, _ := parseMasterEncryptionKey(testHexKey)
	assert.Equal(t, expected, key, "le fichier doit primer sur la variable d'environnement")
	assert.Len(t, key, 32)
}

func TestResolveMasterEncryptionKeyTrimsFileContent(t *testing.T) {
	// Un fichier créé à la main contient presque toujours un retour à la ligne.
	path := filepath.Join(t.TempDir(), "master.key")
	if err := os.WriteFile(path, []byte("  "+testHexKey+"  \n\n"), 0o600); err != nil {
		t.Fatalf("écriture de la clé de test: %v", err)
	}
	t.Setenv("MASTER_ENCRYPTION_KEY", "")
	t.Setenv("MASTER_ENCRYPTION_KEY_PATH", path)

	key, err := resolveMasterEncryptionKey()
	if err != nil {
		t.Fatalf("les espaces et retours à la ligne doivent être tolérés: %v", err)
	}
	assert.Len(t, key, 32)
}

func TestResolveMasterEncryptionKeyFallsBackToEnv(t *testing.T) {
	t.Setenv("MASTER_ENCRYPTION_KEY_PATH", "")
	t.Setenv("MASTER_ENCRYPTION_KEY", testHexKey)

	key, err := resolveMasterEncryptionKey()
	if err != nil {
		t.Fatalf("le repli sur l'environnement doit rester fonctionnel: %v", err)
	}
	assert.Len(t, key, 32)
}

func TestResolveMasterEncryptionKeyReportsUnreadableFile(t *testing.T) {
	// Un chemin défini mais illisible ne doit PAS retomber silencieusement sur
	// l'environnement : ce serait masquer une erreur de configuration.
	t.Setenv("MASTER_ENCRYPTION_KEY", testHexKey)
	t.Setenv("MASTER_ENCRYPTION_KEY_PATH", filepath.Join(t.TempDir(), "absent.key"))

	if _, err := resolveMasterEncryptionKey(); err == nil {
		t.Fatal("un MASTER_ENCRYPTION_KEY_PATH illisible doit remonter une erreur")
	}
}

// Le chiffrement doit être interopérable entre les deux sources : une valeur
// chiffrée avec la clé venue de l'environnement doit se déchiffrer avec la même
// clé lue depuis un fichier. C'est ce qui rend la bascule sûre en production.
func TestEncryptionInteroperableAcrossKeySources(t *testing.T) {
	keyFromEnv, err := parseMasterEncryptionKey(testHexKey)
	if err != nil {
		t.Fatalf("clé de test invalide: %v", err)
	}

	path := filepath.Join(t.TempDir(), "master.key")
	if err := os.WriteFile(path, []byte(testHexKey+"\n"), 0o600); err != nil {
		t.Fatalf("écriture de la clé de test: %v", err)
	}
	t.Setenv("MASTER_ENCRYPTION_KEY", "")
	t.Setenv("MASTER_ENCRYPTION_KEY_PATH", path)
	keyFromFile, err := resolveMasterEncryptionKey()
	if err != nil {
		t.Fatalf("résolution depuis le fichier échouée: %v", err)
	}

	secret := []byte("apple-refresh-token-exemple")
	sealed, err := encryptWith(keyFromEnv, secret)
	if err != nil {
		t.Fatalf("chiffrement échoué: %v", err)
	}
	opened, err := decryptWith(keyFromFile, sealed)
	if err != nil {
		t.Fatalf("déchiffrement avec la clé fichier échoué: %v", err)
	}
	assert.Equal(t, secret, opened)
}

// MARK: - Constat 5 — CORS désactivé par défaut

func TestParseAllowedOrigins(t *testing.T) {
	for _, test := range []struct {
		name  string
		input string
		want  []string
	}{
		{name: "vide", input: "", want: []string{}},
		{name: "espaces seulement", input: "  ,  , ", want: []string{}},
		{name: "une origine", input: "https://web.arbore.app", want: []string{"https://web.arbore.app"}},
		{
			name:  "plusieurs avec espaces",
			input: " https://web.arbore.app , http://localhost:3000 ",
			want:  []string{"https://web.arbore.app", "http://localhost:3000"},
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			assert.Equal(t, test.want, parseAllowedOrigins(test.input))
		})
	}
}

// Sans CORS_ALLOWED_ORIGINS, aucun en-tête CORS ne doit être émis : c'est ce qui
// fait que le navigateur bloque une requête cross-origin.
func TestConfigureCORSDisabledByDefault(t *testing.T) {
	gin.SetMode(gin.TestMode)
	t.Setenv("CORS_ALLOWED_ORIGINS", "")

	router := gin.New()
	configureCORS(router) // ne doit pas paniquer malgré la liste vide
	router.GET("/", func(c *gin.Context) { c.Status(http.StatusOK) })

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Origin", "https://evil.example")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Empty(t, w.Header().Get("Access-Control-Allow-Origin"))
	assert.Empty(t, w.Header().Get("Access-Control-Allow-Credentials"))
}

func TestConfigureCORSAllowsConfiguredOriginOnly(t *testing.T) {
	gin.SetMode(gin.TestMode)
	t.Setenv("CORS_ALLOWED_ORIGINS", "https://web.arbore.app")

	router := gin.New()
	configureCORS(router)
	router.GET("/", func(c *gin.Context) { c.Status(http.StatusOK) })

	allowed := httptest.NewRecorder()
	reqAllowed := httptest.NewRequest(http.MethodGet, "/", nil)
	reqAllowed.Header.Set("Origin", "https://web.arbore.app")
	router.ServeHTTP(allowed, reqAllowed)
	assert.Equal(t, "https://web.arbore.app", allowed.Header().Get("Access-Control-Allow-Origin"))

	// L'ancienne configuration autorisait localhost:3000 en dur, y compris en
	// production : elle ne doit plus être acceptée sans configuration explicite.
	refused := httptest.NewRecorder()
	reqRefused := httptest.NewRequest(http.MethodGet, "/", nil)
	reqRefused.Header.Set("Origin", "http://localhost:3000")
	router.ServeHTTP(refused, reqRefused)
	assert.Empty(t, refused.Header().Get("Access-Control-Allow-Origin"))
}
