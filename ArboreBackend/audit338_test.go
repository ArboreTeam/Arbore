package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// Tests des constats 1, 3, 4, 5 et 8 de l'audit sécurité #338.

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

// MARK: - Constat 1 — RGPD Art. 17, upsert sans destruction de données

func operatorOf(t *testing.T, update bson.M, operator string) bson.M {
	t.Helper()
	fields, ok := update[operator].(bson.M)
	if !ok {
		t.Fatalf("opérateur %s absent ou de type inattendu: %#v", operator, update[operator])
	}
	return fields
}

// LA propriété à ne jamais casser : un second POST /users ne doit pas effacer la
// photo de profil ni le refresh token Apple d'un compte existant. Avant l'upsert,
// `createUser` remettait ces champs à zéro — sans conséquence tant qu'il insérait
// un document neuf, destructeur dès qu'on écrit sur un document existant.
func TestBuildCreateUserUpdateNeverTouchesPreservedFields(t *testing.T) {
	update := buildCreateUserUpdate("user@example.com", "Alice", false, time.Now().UTC())

	preserved := []string{"photoData", "photoContentType", "appleRefreshTokenEncrypted"}
	for _, operator := range []string{"$set", "$setOnInsert"} {
		fields := operatorOf(t, update, operator)
		for _, field := range preserved {
			assert.NotContains(t, fields, field,
				"%s ne doit jamais contenir %s : un compte existant perdrait cette donnée", operator, field)
		}
	}
}

func TestBuildCreateUserUpdateSplitsFieldsCorrectly(t *testing.T) {
	now := time.Date(2026, 7, 26, 12, 0, 0, 0, time.UTC)
	update := buildCreateUserUpdate("user@example.com", "Alice", false, now)

	set := operatorOf(t, update, "$set")
	assert.Equal(t, "user@example.com", set["email"])
	assert.Equal(t, "Alice", set["name"])

	insert := operatorOf(t, update, "$setOnInsert")
	assert.Equal(t, now.Format(time.RFC3339), insert["createdAt"])
	assert.Equal(t, false, insert["banned"])

	// createdAt et banned ne doivent PAS être dans $set : un compte existant
	// garderait sinon la date du dernier appel, et un bannissement serait levé.
	assert.NotContains(t, set, "createdAt")
	assert.NotContains(t, set, "banned")
}

// Un client qui n'envoie pas de nom ne doit pas effacer celui déjà stocké.
func TestBuildCreateUserUpdateOmitsEmptyName(t *testing.T) {
	update := buildCreateUserUpdate("user@example.com", "", false, time.Now().UTC())
	set := operatorOf(t, update, "$set")

	assert.NotContains(t, set, "name", "un nom vide ne doit pas écraser le nom existant")
	assert.Equal(t, "user@example.com", set["email"])
}

// Le marquage des documents de test ne s'applique qu'à la base de test, et
// seulement à l'insertion.
func TestBuildCreateUserUpdateLabelsTestDocumentsOnInsertOnly(t *testing.T) {
	prod := buildCreateUserUpdate("user@example.com", "Alice", false, time.Now().UTC())
	assert.NotContains(t, operatorOf(t, prod, "$setOnInsert"), "_test")

	test := buildCreateUserUpdate("user@example.com", "Alice", true, time.Now().UTC())
	insert := operatorOf(t, test, "$setOnInsert")
	assert.Equal(t, true, insert["_test"])
	assert.Contains(t, insert, "_createdAtUTC")
	// Jamais dans $set : un doc de prod relu par erreur ne doit pas être marqué.
	assert.NotContains(t, operatorOf(t, test, "$set"), "_test")
}

// MARK: - Constat 8 — pas de détail interne dans les réponses d'erreur

func TestRespondInvalidBodyHidesInternalDetail(t *testing.T) {
	gin.SetMode(gin.TestMode)

	router := gin.New()
	router.POST("/x", func(c *gin.Context) {
		var payload struct {
			Name string `json:"name"`
		}
		if err := c.ShouldBindJSON(&payload); err != nil {
			respondInvalidBody(c, err)
			return
		}
		c.Status(http.StatusOK)
	})

	// Corps qui provoque une erreur de binding mentionnant le type Go attendu.
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/x", strings.NewReader(`{"name": 42}`))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
	body := w.Body.String()

	// Le client reçoit un message stable et un code exploitable...
	assert.Contains(t, body, "INVALID_REQUEST_BODY")
	// ...et RIEN des internes Go que produisait `err.Error()`.
	for _, leak := range []string{"json:", "cannot unmarshal", "Go struct field", "of type"} {
		assert.NotContains(t, body, leak, "la réponse ne doit pas exposer le détail du binding")
	}
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
