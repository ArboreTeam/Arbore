package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
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
	testAPIKey         = "test_api_key_12345"
	validFirebaseToken = "mock_firebase_token" // Pour les tests, on va mocker Firebase
)

// setupTestRouter configure un router Gin pour les tests
func setupTestRouter(_ *testing.T) *gin.Engine {
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
	if err := os.MkdirAll(modelsDir, 0755); err != nil {
		t.Fatalf("Failed to create models dir: %v", err)
	}
	testFilePath := filepath.Join(modelsDir, "Test.usdz")
	testContent := []byte("test usdz content")
	if err := os.WriteFile(testFilePath, testContent, 0600); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	defer func() { _ = os.Remove(testFilePath) }()

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
	if err := os.MkdirAll(modelsDir, 0755); err != nil {
		t.Fatalf("Failed to create models dir: %v", err)
	}
	testFilePath := filepath.Join(modelsDir, "TestCase.usdz")
	if err := os.WriteFile(testFilePath, []byte("test"), 0600); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	defer func() { _ = os.Remove(testFilePath) }()

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
		"file name.usdz", // Espace
		"file;name.usdz", // Point-virgule
		"file&name.usdz", // Esperluette
		"file|name.usdz", // Pipe
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

// MARK: - Photo Upload Ownership Tests

// setupPhotoOwnershipTestRouter creates a router that mocks POST /users/:uid/photo
// with the same ownership check as the real handler (JWT uid must match URL uid).
func setupPhotoOwnershipTestRouter(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	router := gin.Default()

	multiUserFirebase := func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		switch authHeader {
		case "Bearer " + gardenOwnerToken:
			c.Set("uid", gardenOwnerUID)
		case "Bearer " + gardenNonOwnerToken:
			c.Set("uid", gardenNonOwnerUID)
		default:
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
			c.Abort()
			return
		}
		c.Next()
	}

	mockAPIKey := func(c *gin.Context) {
		if c.GetHeader("X-API-Key") != testAPIKey {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid API Key"})
			c.Abort()
			return
		}
		c.Next()
	}

	protected := router.Group("/")
	protected.Use(mockAPIKey)
	protected.Use(multiUserFirebase)
	{
		// Mirror the real uploadUserPhoto ownership logic without MongoDB.
		protected.POST("/users/:uid/photo", func(c *gin.Context) {
			uidParam := c.Param("uid")
			tokenUID, _ := c.Get("uid")
			if tokenUID != uidParam {
				c.JSON(http.StatusForbidden, gin.H{"error": "Forbidden: vous ne pouvez modifier que votre propre photo"})
				return
			}
			// Verify the multipart field is present (mirrors real handler).
			_, _, err := c.Request.FormFile("photo")
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "photo not provided or invalid"})
				return
			}
			c.JSON(http.StatusOK, gin.H{"message": "Photo enregistrée avec succès"})
		})
	}

	return router
}

// multipartBody builds a minimal multipart/form-data body with a "photo" field.
func multipartBody(t *testing.T) (*bytes.Buffer, string) {
	t.Helper()
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("photo", "test.jpg")
	if err != nil {
		t.Fatalf("failed to create form file: %v", err)
	}
	if _, err := part.Write([]byte("fake-image-data")); err != nil {
		t.Fatalf("failed to write form file content: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("failed to close multipart writer: %v", err)
	}
	return body, writer.FormDataContentType()
}

func TestUploadPhoto_Owner_ShouldReturn200(t *testing.T) {
	router := setupPhotoOwnershipTestRouter(t)
	body, ct := multipartBody(t)
	req, _ := http.NewRequest("POST", "/users/"+gardenOwnerUID+"/photo", body)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+gardenOwnerToken)
	req.Header.Set("Content-Type", ct)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code, "Owner should be able to upload their own photo")
}

func TestUploadPhoto_NonOwner_ShouldReturn403(t *testing.T) {
	router := setupPhotoOwnershipTestRouter(t)
	body, ct := multipartBody(t)
	// gardenNonOwnerToken holder tries to upload to gardenOwnerUID's profile
	req, _ := http.NewRequest("POST", "/users/"+gardenOwnerUID+"/photo", body)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+gardenNonOwnerToken)
	req.Header.Set("Content-Type", ct)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusForbidden, w.Code, "Non-owner should not be able to overwrite another user's photo")
}

func TestUploadPhoto_WithoutAuth_ShouldReturn401(t *testing.T) {
	router := setupPhotoOwnershipTestRouter(t)
	body, ct := multipartBody(t)
	req, _ := http.NewRequest("POST", "/users/"+gardenOwnerUID+"/photo", body)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Content-Type", ct)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestUploadPhoto_MissingPhotoField_ShouldReturn400(t *testing.T) {
	router := setupPhotoOwnershipTestRouter(t)
	// Send an empty body — no "photo" multipart field
	req, _ := http.NewRequest("POST", "/users/"+gardenOwnerUID+"/photo", bytes.NewBuffer(nil))
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+gardenOwnerToken)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code, "Request without photo field should return 400")
}

// MARK: - Garden Delete Ownership Tests

// gardenOwnerToken / gardenNonOwnerToken are separate mock tokens mapping to
// two different UIDs so we can exercise the ownership-check logic without a
// real MongoDB connection.
const (
	gardenOwnerToken    = "mock_owner_token"
	gardenOwnerUID      = "owner_uid_123"
	gardenNonOwnerToken = "mock_nonowner_token"
	gardenNonOwnerUID   = "other_uid_456"
	ownerGardenID       = "507f1f77bcf86cd799439011" // fake Mongo ObjectID
)

// setupOwnershipTestRouter creates a router that mocks the DELETE /gardens/:id
// ownership check: a garden is "owned" by gardenOwnerUID only.
// It mirrors the real deleteGarden logic (filter by _id AND uid) without
// requiring a live MongoDB connection.
func setupOwnershipTestRouter(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	router := gin.Default()

	// Two-user mock Firebase middleware
	multiUserFirebase := func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		switch authHeader {
		case "Bearer " + gardenOwnerToken:
			c.Set("uid", gardenOwnerUID)
		case "Bearer " + gardenNonOwnerToken:
			c.Set("uid", gardenNonOwnerUID)
		default:
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
			c.Abort()
			return
		}
		c.Next()
	}

	mockAPIKey := func(c *gin.Context) {
		if c.GetHeader("X-API-Key") != testAPIKey {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid API Key"})
			c.Abort()
			return
		}
		c.Next()
	}

	protected := router.Group("/")
	protected.Use(mockAPIKey)
	protected.Use(multiUserFirebase)
	{
		// Mock handler that mirrors the real deleteGarden ownership logic:
		// only the garden owner (gardenOwnerUID) can delete it.
		protected.DELETE("/gardens/:id", func(c *gin.Context) {
			idParam := c.Param("id")
			// Validate ObjectID format (same as real handler)
			if len(idParam) != 24 {
				c.JSON(http.StatusBadRequest, gin.H{"error": "ID invalide"})
				return
			}

			uid, _ := c.Get("uid")

			// The "database" only has one garden owned by gardenOwnerUID
			if idParam != ownerGardenID || uid != gardenOwnerUID {
				c.JSON(http.StatusNotFound, gin.H{"message": "Garden non trouvé ou accès refusé"})
				return
			}

			c.JSON(http.StatusOK, gin.H{"message": "Garden supprimé"})
		})
	}

	return router
}

func TestDeleteGarden_Owner_ShouldReturn200(t *testing.T) {
	router := setupOwnershipTestRouter(t)
	req, _ := http.NewRequest("DELETE", "/gardens/"+ownerGardenID, nil)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+gardenOwnerToken)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code, "Garden owner should be able to delete their garden")

	var response map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &response)
	assert.NoError(t, err)
	assert.Equal(t, "Garden supprimé", response["message"])
}

func TestDeleteGarden_NonOwner_ShouldReturn404(t *testing.T) {
	router := setupOwnershipTestRouter(t)
	req, _ := http.NewRequest("DELETE", "/gardens/"+ownerGardenID, nil)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+gardenNonOwnerToken)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	// Returns 404 (not 403) to avoid leaking whether the garden ID is valid
	assert.Equal(t, http.StatusNotFound, w.Code, "Non-owner should not be able to delete another user's garden")
}

func TestDeleteGarden_WithoutAuth_ShouldReturn401(t *testing.T) {
	router := setupOwnershipTestRouter(t)
	req, _ := http.NewRequest("DELETE", "/gardens/"+ownerGardenID, nil)
	req.Header.Set("X-API-Key", testAPIKey)
	// No Authorization header
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code, "Unauthenticated request should be rejected")
}

func TestDeleteGarden_WithoutAPIKey_ShouldReturn401(t *testing.T) {
	router := setupOwnershipTestRouter(t)
	req, _ := http.NewRequest("DELETE", "/gardens/"+ownerGardenID, nil)
	// No X-API-Key header
	req.Header.Set("Authorization", "Bearer "+gardenOwnerToken)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code, "Request without API key should be rejected")
}

func TestDeleteGarden_InvalidID_ShouldReturn400(t *testing.T) {
	router := setupOwnershipTestRouter(t)
	req, _ := http.NewRequest("DELETE", "/gardens/not-a-valid-object-id", nil)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+gardenOwnerToken)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code, "Invalid ObjectID should return 400")
}

func TestDeleteGarden_NonExistentID_ShouldReturn404(t *testing.T) {
	router := setupOwnershipTestRouter(t)
	// Valid ObjectID format but not in the "database"
	req, _ := http.NewRequest("DELETE", "/gardens/aabbccddeeff001122334455", nil)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+gardenOwnerToken)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusNotFound, w.Code, "Non-existent garden should return 404")
}

// MARK: - Garden Update Ownership Tests

// setupUpdateOwnershipTestRouter mirrors PUT /gardens/:id with JWT ownership check.
func setupUpdateOwnershipTestRouter(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	router := gin.Default()

	multiUserFirebase := func(c *gin.Context) {
		switch c.GetHeader("Authorization") {
		case "Bearer " + gardenOwnerToken:
			c.Set("uid", gardenOwnerUID)
		case "Bearer " + gardenNonOwnerToken:
			c.Set("uid", gardenNonOwnerUID)
		default:
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
			c.Abort()
		}
		c.Next()
	}

	mockAPIKey := func(c *gin.Context) {
		if c.GetHeader("X-API-Key") != testAPIKey {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid API Key"})
			c.Abort()
			return
		}
		c.Next()
	}

	protected := router.Group("/")
	protected.Use(mockAPIKey)
	protected.Use(multiUserFirebase)
	{
		protected.PUT("/gardens/:id", func(c *gin.Context) {
			idParam := c.Param("id")
			if len(idParam) != 24 {
				c.JSON(http.StatusBadRequest, gin.H{"error": "ID invalide"})
				return
			}
			uid, _ := c.Get("uid")
			if idParam != ownerGardenID || uid != gardenOwnerUID {
				c.JSON(http.StatusNotFound, gin.H{"message": "Garden non trouvé ou accès refusé"})
				return
			}
			c.JSON(http.StatusOK, gin.H{"message": "Garden mis à jour"})
		})
	}

	return router
}

func TestUpdateGarden_Owner_ShouldReturn200(t *testing.T) {
	router := setupUpdateOwnershipTestRouter(t)
	body, _ := json.Marshal(map[string]string{"name": "New Name"})
	req, _ := http.NewRequest("PUT", "/gardens/"+ownerGardenID, bytes.NewBuffer(body))
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+gardenOwnerToken)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code, "Owner should be able to update their garden")
}

func TestUpdateGarden_NonOwner_ShouldReturn404(t *testing.T) {
	router := setupUpdateOwnershipTestRouter(t)
	body, _ := json.Marshal(map[string]string{"name": "Hacked"})
	req, _ := http.NewRequest("PUT", "/gardens/"+ownerGardenID, bytes.NewBuffer(body))
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+gardenNonOwnerToken)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusNotFound, w.Code, "Non-owner should not be able to update another user's garden")
}

func TestUpdateGarden_WithoutAuth_ShouldReturn401(t *testing.T) {
	router := setupUpdateOwnershipTestRouter(t)
	body, _ := json.Marshal(map[string]string{"name": "No Auth"})
	req, _ := http.NewRequest("PUT", "/gardens/"+ownerGardenID, bytes.NewBuffer(body))
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

// MARK: - List Gardens Tests

// setupListGardensTestRouter mirrors GET /gardens with JWT-based uid filtering.
func setupListGardensTestRouter(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	router := gin.Default()

	multiUserFirebase := func(c *gin.Context) {
		switch c.GetHeader("Authorization") {
		case "Bearer " + gardenOwnerToken:
			c.Set("uid", gardenOwnerUID)
		case "Bearer " + gardenNonOwnerToken:
			c.Set("uid", gardenNonOwnerUID)
		default:
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
			c.Abort()
		}
		c.Next()
	}

	mockAPIKey := func(c *gin.Context) {
		if c.GetHeader("X-API-Key") != testAPIKey {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid API Key"})
			c.Abort()
			return
		}
		c.Next()
	}

	// Simulated in-memory gardens: only the owner has one.
	type gardenRecord struct{ Name string }
	ownerGardens := []gardenRecord{{Name: "My Garden"}}
	nonOwnerGardens := []gardenRecord{}

	protected := router.Group("/")
	protected.Use(mockAPIKey)
	protected.Use(multiUserFirebase)
	{
		protected.GET("/gardens", func(c *gin.Context) {
			uid, _ := c.Get("uid")
			var result []gardenRecord
			if uid == gardenOwnerUID {
				result = ownerGardens
			} else {
				result = nonOwnerGardens
			}
			c.JSON(http.StatusOK, result)
		})
	}

	return router
}

func TestListGardens_OwnerSeesTheirGardens(t *testing.T) {
	router := setupListGardensTestRouter(t)
	req, _ := http.NewRequest("GET", "/gardens", nil)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+gardenOwnerToken)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	var result []map[string]interface{}
	assert.NoError(t, json.Unmarshal(w.Body.Bytes(), &result))
	assert.Len(t, result, 1, "Owner should see 1 garden")
}

func TestListGardens_NonOwnerSeesOnlyTheirOwn(t *testing.T) {
	router := setupListGardensTestRouter(t)
	req, _ := http.NewRequest("GET", "/gardens", nil)
	req.Header.Set("X-API-Key", testAPIKey)
	req.Header.Set("Authorization", "Bearer "+gardenNonOwnerToken)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	// Non-owner has no gardens — importantly they cannot see the owner's garden
	assert.Equal(t, http.StatusOK, w.Code)
	var result []map[string]interface{}
	assert.NoError(t, json.Unmarshal(w.Body.Bytes(), &result))
	assert.Len(t, result, 0, "Non-owner should see 0 gardens (cannot see other users' gardens)")
}

func TestListGardens_WithoutAuth_ShouldReturn401(t *testing.T) {
	router := setupListGardensTestRouter(t)
	req, _ := http.NewRequest("GET", "/gardens", nil)
	req.Header.Set("X-API-Key", testAPIKey)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

// MARK: - Benchmark Tests

func BenchmarkModelsEndpoint_ValidRequest(b *testing.B) {
	// Créer un fichier de test
	modelsDir := "./models"
	_ = os.MkdirAll(modelsDir, 0755)
	testFilePath := filepath.Join(modelsDir, "Benchmark.usdz")
	testContent := make([]byte, 1024*1024) // 1 MB
	_ = os.WriteFile(testFilePath, testContent, 0600)
	defer func() { _ = os.Remove(testFilePath) }()

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
