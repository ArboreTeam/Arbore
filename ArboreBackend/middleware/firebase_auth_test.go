package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestIsReleaseMode(t *testing.T) {
	t.Setenv("GIN_MODE", "release")
	if !isReleaseMode() {
		t.Error("expected release mode when GIN_MODE=release")
	}

	t.Setenv("GIN_MODE", "debug")
	if isReleaseMode() {
		t.Error("expected non-release mode when GIN_MODE=debug")
	}

	t.Setenv("GIN_MODE", "")
	if isReleaseMode() {
		t.Error("expected non-release mode when GIN_MODE unset")
	}
}

func TestInitFirebase_ReleaseMode_MissingPath_Fails(t *testing.T) {
	t.Setenv("GIN_MODE", "release")
	t.Setenv("FIREBASE_SERVICE_ACCOUNT_PATH", "")

	if err := InitFirebase(); err == nil {
		t.Fatal("expected error in release mode when FIREBASE_SERVICE_ACCOUNT_PATH is missing")
	}
}

func TestInitFirebase_ReleaseMode_InvalidPath_Fails(t *testing.T) {
	t.Setenv("GIN_MODE", "release")
	t.Setenv("FIREBASE_SERVICE_ACCOUNT_PATH", "/nonexistent/firebase-adminsdk.json")

	if err := InitFirebase(); err == nil {
		t.Fatal("expected error in release mode when FIREBASE credentials file is missing")
	}
}

func TestInitFirebase_DevMode_MissingPath_AllowsStartup(t *testing.T) {
	t.Setenv("GIN_MODE", "debug")
	t.Setenv("FIREBASE_SERVICE_ACCOUNT_PATH", "")

	if err := InitFirebase(); err != nil {
		t.Fatalf("expected nil error in dev mode with missing path, got %v", err)
	}
}

func TestInitFirebase_DevMode_InvalidPath_AllowsStartup(t *testing.T) {
	t.Setenv("GIN_MODE", "debug")
	t.Setenv("FIREBASE_SERVICE_ACCOUNT_PATH", "/nonexistent/firebase-adminsdk.json")

	if err := InitFirebase(); err != nil {
		t.Fatalf("expected nil error in dev mode with invalid path, got %v", err)
	}
}

// TestMiddleware_NilFirebaseAuth_ReleaseMode_Returns503 verifies that the middleware
// fails closed: when firebaseAuth is nil in release mode, requests are refused with 503
// rather than being let through with an "unauthenticated" UID.
func TestMiddleware_NilFirebaseAuth_ReleaseMode_Returns503(t *testing.T) {
	t.Setenv("GIN_MODE", "release")
	firebaseAuth = nil

	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(FirebaseAuthMiddleware())
	router.GET("/protected", func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer fake-token")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != 503 {
		t.Errorf("expected 503 in release mode with nil firebaseAuth, got %d (body: %s)", w.Code, w.Body.String())
	}
}

// TestMiddleware_NilFirebaseAuth_DevMode_AllowsRequest verifies the dev-mode
// convenience: backend can run without Firebase credentials and requests pass
// through with uid="unauthenticated".
func TestMiddleware_NilFirebaseAuth_DevMode_AllowsRequest(t *testing.T) {
	t.Setenv("GIN_MODE", "debug")
	firebaseAuth = nil

	gin.SetMode(gin.TestMode)
	router := gin.New()
	var seenUID string
	router.Use(FirebaseAuthMiddleware())
	router.GET("/protected", func(c *gin.Context) {
		if v, ok := c.Get("uid"); ok {
			seenUID = v.(string)
		}
		c.JSON(200, gin.H{"ok": true})
	})

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer fake-token")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Errorf("expected 200 in dev mode, got %d", w.Code)
	}
	if seenUID != "unauthenticated" {
		t.Errorf("expected uid=unauthenticated in dev mode, got %q", seenUID)
	}
}

func TestMiddleware_MissingAuthHeader_Returns401(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(FirebaseAuthMiddleware())
	router.GET("/protected", func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != 401 {
		t.Errorf("expected 401 for missing Authorization header, got %d", w.Code)
	}
}

func TestMiddleware_InvalidAuthFormat_Returns401(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(FirebaseAuthMiddleware())
	router.GET("/protected", func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "NotBearer token")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != 401 {
		t.Errorf("expected 401 for invalid auth format, got %d", w.Code)
	}
}

func TestEmailVerificationIsNotRequiredForAccountLifecycle(t *testing.T) {
	if requiresVerifiedEmail(http.MethodPost, "/users") {
		t.Fatal("account creation should be available before email verification")
	}
	if requiresVerifiedEmail(http.MethodDelete, "/users") {
		t.Fatal("account deletion should be available before email verification")
	}
	if !requiresVerifiedEmail(http.MethodGet, "/gardens") {
		t.Fatal("business routes should still require a verified email")
	}
}
