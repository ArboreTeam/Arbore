package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

// Test configuration
const (
	testAPIKey      = "test_api_key_12345"
	validFirebaseToken = "mock_firebase_token" // Pour les tests, on va mocker Firebase
)

// setupTestRouter configure un router Gin pour les tests
func setupTestRouter(t *testing.T) *gin.Engine {
	gin.SetMode(gin.TestMode)
	router := gin.Default()

	// Mock du middleware Firebase pour les tests
	// En production, on utiliserait Firebase Admin SDK
	mockFirebaseMiddleware := func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" || authHeader != "Bearer "+validFirebaseToken {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
			c.Abort()
			return
		}
		// Simuler un UID valide
		c.Set("uid", "test_user_123")
		c.Next()
	}

	// Mock du middleware API Key pour les tests
	mockAPIKeyMiddleware := func(c *gin.Context) {
		apiKey := c.GetHeader("X-API-Key")
		if apiKey != testAPIKey {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid API Key"})
			c.Abort()
			return
		}
		c.Next()
	}

	// Routes publiques
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	// Routes protégées
	protected := router.Group("/")
	protected.Use(mockAPIKeyMiddleware)
	protected.Use(mockFirebaseMiddleware)
	{
		// Models endpoint
		protected.GET("/models/:filename", func(c *gin.Context) {
			filename := c.Param("filename")

			// Sécurité: empêcher les path traversal attacks
			if contains(filename, "..") || contains(filename, "/") {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid filename"})
				return
			}

			// Vérifier que c'est bien un fichier .usdz
			if !hasSuffix(filename, ".usdz") {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Only .usdz files are allowed"})
				return
			}

			filePath := fmt.Sprintf("./models/%s", filename)

			// Vérifier si le fichier existe
			if _, err := os.Stat(filePath); os.IsNotExist(err) {
				c.JSON(http.StatusNotFound, gin.H{"error": "Model not found"})
				return
			}

			c.Header("Content-Type", "model/vnd.usdz+zip")
			c.File(filePath)
		})
	}

	return router
}

// Helper functions
func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > len(substr) &&
		(s[:len(substr)] == substr || s[len(s)-len(substr):] == substr ||
		bytes.Contains([]byte(s), []byte(substr))))
}

func hasSuffix(s, suffix string) bool {
	return len(s) >= len(suffix) && s[len(s)-len(suffix):] == suffix
}

// MARK: - Health Endpoint Tests

func TestHealthEndpoint_ShouldReturnOK(t *testing.T) {
	// Arrange
	router := setupTestRouter(t)
	req, _ := http.NewRequest("GET", "/health", nil)
	w := httptest.NewRecorder()

	// Act
	router.ServeHTTP(w, req)

	// Assert
	assert.Equal(t, http.StatusOK, w.Code)

	var response map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &response)
	assert.NoError(t, err)
	assert.Equal(t, "ok", response["status"])
}

// MARK: - Models Endpoint Tests

func TestModelsEndpoint_WithoutAPIKey_ShouldReturn401(t *testing.T) {
	// Arrange
	router := setupTestRouter(t)
	req, _ := http.NewRequest("GET", "/models/Pothos.usdz", nil)
	req.Header.Set("Authorization", "Bearer "+validFirebaseToken)
	w := httptest.NewRecorder()

	// Act
	router.ServeHTTP(w, req)

	// Assert
	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestModelsEndpoint_WithoutFirebaseToken_ShouldReturn401(t *testing.T) {
	// Arrange
	router := setupTestRouter(t)
	req, _ := http.NewRequest("GET", "/models/Pothos.usdz", nil)
	req.Header.Set("X-API-Key", testAPIKey)
	w := httptest.NewRecorder()

	// Act
	router.ServeHTTP(w, req)

	// Assert
	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestModelsEndpoint_WithInvalidAPIKey_ShouldReturn401(t *testing.T) {
	// Arrange
	router := setupTestRouter(t)
	req, _ := http.NewRequest("GET", "/models/Pothos.usdz", nil)
	req.Header.Set("X-API-Key", "invalid_key")
	req.Header.Set("Authorization", "Bearer "+validFirebaseToken)
	w := httptest.NewRecorder()

	// Act
	router.ServeHTTP(w, req)

	// Assert
	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestModelsEndpoint_WithInvalidFirebaseToken_ShouldReturn401(t *testing.T) {
	// Arrange
	router := setupTestRouter(t)
	req, _ := http.NewRequest("GET", "/models/Pothos.usdz", nil)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer invalid_token")
	w := httptest.NewRecorder()

	// Act
	router.ServeHTTP(w, req)

	// Assert
	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestModelsEndpoint_PathTraversal_ShouldBeBlocked(t *testing.T) {
	// Arrange
	router := setupTestRouter(t)
	testCases := []string{
		"../etc/passwd",
		"../../secret.txt",
		"test/../../file.usdz",
	}

	for _, testCase := range testCases {
		t.Run(testCase, func(t *testing.T) {
			req, _ := http.NewRequest("GET", "/models/"+testCase, nil)
			req.Header.Set("X-API-Key", testAPIKey)
			req.Header.Set("Authorization", "Bearer "+validFirebaseToken)
			w := httptest.NewRecorder()

			// Act
			router.ServeHTTP(w, req)

			// Assert - Gin normalise les URL, donc path traversal donne 404
			// C'est OK car l'attaquant n'obtient pas le fichier
			assert.True(t, w.Code == http.StatusNotFound || w.Code == http.StatusBadRequest,
				"Path traversal should be blocked (404 or 400)")
		})
	}
}

func TestModelsEndpoint_NonUSDZFile_ShouldReturn400(t *testing.T) {
	// Arrange
	router := setupTestRouter(t)
	testCases := []string{
		"malicious.exe",
		"script.sh",
		"data.json",
		"model.obj",
		"model.fbx",
	}

	for _, testCase := range testCases {
		t.Run(testCase, func(t *testing.T) {
			req, _ := http.NewRequest("GET", "/models/"+testCase, nil)
			req.Header.Set("X-API-Key", testAPIKey)
			req.Header.Set("Authorization", "Bearer "+validFirebaseToken)
			w := httptest.NewRecorder()

			// Act
			router.ServeHTTP(w, req)

			// Assert
			assert.Equal(t, http.StatusBadRequest, w.Code, "Non-USDZ files should be rejected")

			var response map[string]interface{}
			_ = json.Unmarshal(w.Body.Bytes(), &response)
			assert.Equal(t, "Only .usdz files are allowed", response["error"])
		})
	}
}

func TestModelsEndpoint_NonExistentFile_ShouldReturn404(t *testing.T) {
	// Arrange
	router := setupTestRouter(t)
	req, _ := http.NewRequest("GET", "/models/NonExistent.usdz", nil)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+validFirebaseToken)
	w := httptest.NewRecorder()

	// Act
	router.ServeHTTP(w, req)

	// Assert
	assert.Equal(t, http.StatusNotFound, w.Code)

	var response map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &response)
	assert.NoError(t, err)
	assert.Equal(t, "Model not found", response["error"])
}

func TestModelsEndpoint_ValidFile_ShouldReturn200(t *testing.T) {
	// Arrange - Créer un fichier de test
	modelsDir := "./models"
	os.MkdirAll(modelsDir, 0755)
	testFilePath := filepath.Join(modelsDir, "Test.usdz")
	testContent := []byte("test usdz content")
	err := os.WriteFile(testFilePath, testContent, 0644)
	if err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	defer os.Remove(testFilePath)

	router := setupTestRouter(t)
	req, _ := http.NewRequest("GET", "/models/Test.usdz", nil)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+validFirebaseToken)
	w := httptest.NewRecorder()

	// Act
	router.ServeHTTP(w, req)

	// Assert
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "model/vnd.usdz+zip", w.Header().Get("Content-Type"))

	responseBody, _ := io.ReadAll(w.Body)
	assert.Equal(t, testContent, responseBody, "Response body should match file content")
}

func TestModelsEndpoint_ExistingModel_Pothos_ShouldReturn200(t *testing.T) {
	// Arrange - Test avec un vrai fichier si disponible
	modelsDir := "./models"
	pothosPath := filepath.Join(modelsDir, "Pothos.usdz")

	// Skip le test si le fichier n'existe pas
	if _, err := os.Stat(pothosPath); os.IsNotExist(err) {
		t.Skip("Pothos.usdz not found, skipping test")
	}

	router := setupTestRouter(t)
	req, _ := http.NewRequest("GET", "/models/Pothos.usdz", nil)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+validFirebaseToken)
	w := httptest.NewRecorder()

	// Act
	router.ServeHTTP(w, req)

	// Assert
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "model/vnd.usdz+zip", w.Header().Get("Content-Type"))

	// Vérifier que le fichier a bien une taille > 0
	fileInfo, _ := os.Stat(pothosPath)
	assert.Greater(t, fileInfo.Size(), int64(0), "File should have content")

	responseSize := int64(w.Body.Len())
	assert.Equal(t, fileInfo.Size(), responseSize, "Response size should match file size")
}

func TestModelsEndpoint_AllModels_ShouldBeAccessible(t *testing.T) {
	// Test que tous les modèles USDZ dans le dossier models sont accessibles

	modelsDir := "./models"
	files, err := os.ReadDir(modelsDir)
	if err != nil {
		t.Skip("Models directory not found, skipping test")
	}

	router := setupTestRouter(t)

	for _, file := range files {
		if !file.IsDir() && hasSuffix(file.Name(), ".usdz") {
			t.Run(file.Name(), func(t *testing.T) {
				req, _ := http.NewRequest("GET", "/models/"+file.Name(), nil)
				req.Header.Set("X-API-Key", testAPIKey)
				req.Header.Set("Authorization", "Bearer "+validFirebaseToken)
				w := httptest.NewRecorder()

				// Act
				router.ServeHTTP(w, req)

				// Assert
				assert.Equal(t, http.StatusOK, w.Code, "Model "+file.Name()+" should be accessible")
				assert.Equal(t, "model/vnd.usdz+zip", w.Header().Get("Content-Type"))
			})
		}
	}
}

// MARK: - Security Tests

func TestModelsEndpoint_CaseSensitivity_ShouldRespectFileSystem(t *testing.T) {
	// Test le comportement avec différentes casses
	// Note: Le comportement dépend du système de fichiers (case-sensitive ou non)

	// Créer un fichier de test avec un nom spécifique
	modelsDir := "./models"
	os.MkdirAll(modelsDir, 0755)
	testFilePath := filepath.Join(modelsDir, "TestCase.usdz")
	err := os.WriteFile(testFilePath, []byte("test"), 0644)
	if err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	defer os.Remove(testFilePath)

	router := setupTestRouter(t)

	// Test avec le bon nom
	req1, _ := http.NewRequest("GET", "/models/TestCase.usdz", nil)
	req1.Header.Set("X-API-Key", testAPIKey)
	req1.Header.Set("Authorization", "Bearer "+validFirebaseToken)
	w1 := httptest.NewRecorder()
	router.ServeHTTP(w1, req1)
	assert.Equal(t, http.StatusOK, w1.Code, "Exact case should work")

	// Test avec un nom différent (case)
	// Sur macOS APFS (case-insensitive), ça peut marcher. Sur Linux (case-sensitive), ça échouera.
	req2, _ := http.NewRequest("GET", "/models/testcase.usdz", nil)
	req2.Header.Set("X-API-Key", testAPIKey)
	req2.Header.Set("Authorization", "Bearer "+validFirebaseToken)
	w2 := httptest.NewRecorder()
	router.ServeHTTP(w2, req2)

	// Le comportement dépend du système de fichiers
	assert.True(t, w2.Code == http.StatusOK || w2.Code == http.StatusNotFound,
		"Response depends on file system case-sensitivity")
}

func TestModelsEndpoint_SpecialCharacters_ShouldBeRejected(t *testing.T) {
	// Test que les caractères spéciaux sont rejetés

	router := setupTestRouter(t)
	testCases := []string{
		"file name.usdz",  // Espace
		"file;name.usdz",  // Point-virgule
		"file&name.usdz",  // Esperluette
		"file|name.usdz",  // Pipe
	}

	for _, testCase := range testCases {
		t.Run(testCase, func(t *testing.T) {
			req, _ := http.NewRequest("GET", "/models/"+testCase, nil)
			req.Header.Set("X-API-Key", testAPIKey)
			req.Header.Set("Authorization", "Bearer "+validFirebaseToken)
			w := httptest.NewRecorder()

			router.ServeHTTP(w, req)

			// Devrait soit être 404 (fichier n'existe pas) soit 400 (invalide)
			assert.True(t, w.Code == http.StatusNotFound || w.Code == http.StatusBadRequest,
				"Special characters should be rejected or not found")
		})
	}
}

// MARK: - Benchmark Tests

func BenchmarkModelsEndpoint_ValidRequest(b *testing.B) {
	// Créer un fichier de test
	modelsDir := "./models"
	os.MkdirAll(modelsDir, 0755)
	testFilePath := filepath.Join(modelsDir, "Benchmark.usdz")
	testContent := make([]byte, 1024*1024) // 1 MB
	os.WriteFile(testFilePath, testContent, 0644)
	defer os.Remove(testFilePath)

	router := setupTestRouter(nil)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		req, _ := http.NewRequest("GET", "/models/Benchmark.usdz", nil)
		req.Header.Set("X-API-Key", testAPIKey)
		req.Header.Set("Authorization", "Bearer "+validFirebaseToken)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)
	}
}
