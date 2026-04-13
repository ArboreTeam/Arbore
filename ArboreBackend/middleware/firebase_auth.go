package middleware

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"github.com/gin-gonic/gin"
	"google.golang.org/api/option"
)

var firebaseAuth *auth.Client

// CheckUserBannedFunc is a function to check if a user is banned in the database
var CheckUserBannedFunc func(string) (bool, error)

// isReleaseMode reports whether the server runs in production.
// In release mode Firebase auth is REQUIRED — any missing credential must fail fast.
func isReleaseMode() bool {
	return os.Getenv("GIN_MODE") == "release"
}

// InitFirebase initializes the Firebase Admin SDK using the service account file.
// In release mode, any credential problem is fatal: the backend must refuse to
// start rather than running with authentication disabled.
func InitFirebase() error {
	serviceAccountPath := os.Getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
	if serviceAccountPath == "" {
		if isReleaseMode() {
			return fmt.Errorf("FIREBASE_SERVICE_ACCOUNT_PATH is required in release mode")
		}
		log.Println("⚠️  FIREBASE_SERVICE_ACCOUNT_PATH non défini, auth Firebase désactivée (dev only)")
		return nil
	}

	// Check that the file exists and is a regular file (not a directory)
	info, err := os.Stat(serviceAccountPath)
	if err != nil {
		if isReleaseMode() {
			return fmt.Errorf("firebase credentials file unreadable in release mode (%s): %w", serviceAccountPath, err)
		}
		log.Printf("⚠️  Fichier Firebase introuvable (%s): %v — auth Firebase désactivée (dev only)", serviceAccountPath, err)
		return nil
	}
	if info.IsDir() {
		if isReleaseMode() {
			return fmt.Errorf("FIREBASE_SERVICE_ACCOUNT_PATH points to a directory in release mode: %s", serviceAccountPath)
		}
		log.Printf("⚠️  FIREBASE_SERVICE_ACCOUNT_PATH pointe vers un dossier, pas un fichier (%s) — auth Firebase désactivée (dev only)", serviceAccountPath)
		return nil
	}

	// Read service account file
	// nolint:gosec // serviceAccountPath comes from trusted FIREBASE_SERVICE_ACCOUNT_PATH environment variable
	serviceAccountJSON, err := os.ReadFile(serviceAccountPath)
	if err != nil {
		return err
	}

	// nolint:staticcheck // WithCredentialsJSON is the recommended approach for server environments with explicit credential files
	opt := option.WithCredentialsJSON(serviceAccountJSON)
	app, err := firebase.NewApp(context.Background(), nil, opt)
	if err != nil {
		return err
	}

	firebaseAuth, err = app.Auth(context.Background())
	if err != nil {
		return err
	}

	log.Println("✅ Firebase Admin SDK initialisé")
	return nil
}

// FirebaseAuthMiddleware validates Firebase ID tokens and extracts user UID
func FirebaseAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(401, gin.H{
				"error": "Authorization header required",
				"code":  "MISSING_AUTH_HEADER",
			})
			c.Abort()
			return
		}

		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(401, gin.H{
				"error": "Invalid authorization header format (expected: Bearer <token>)",
				"code":  "INVALID_AUTH_FORMAT",
			})
			c.Abort()
			return
		}

		idToken := parts[1]

		// Si Firebase n'est pas initialisé, fail-closed en prod, fail-open en dev.
		// En release mode, InitFirebase() aurait dû empêcher le démarrage du backend,
		// donc atteindre ce point signifie qu'un bug ou une race a laissé firebaseAuth nil
		// — on refuse la requête au lieu de laisser passer sans authentification.
		if firebaseAuth == nil {
			if isReleaseMode() {
				log.Println("❌ Firebase non initialisé en release mode — requête refusée")
				c.JSON(503, gin.H{
					"error": "Authentication service unavailable",
					"code":  "AUTH_UNAVAILABLE",
				})
				c.Abort()
				return
			}
			log.Println("⚠️  Firebase non initialisé — token non vérifié, auth désactivée (dev only)")
			c.Set("uid", "unauthenticated")
			c.Next()
			return
		}

		token, err := firebaseAuth.VerifyIDToken(context.Background(), idToken)
		if err != nil {
			log.Printf("❌ Token validation failed: %v", err)
			c.JSON(401, gin.H{
				"error": "Invalid or expired token",
				"code":  "INVALID_TOKEN",
			})
			c.Abort()
			return
		}

		uid := token.UID

		if CheckUserBannedFunc != nil {
			banned, err := CheckUserBannedFunc(uid)
			if err != nil {
				log.Printf("❌ Error checking ban status: %v", err)
				c.JSON(500, gin.H{
					"error": "Internal server error",
					"code":  "DATABASE_ERROR",
				})
				c.Abort()
				return
			}

			if banned {
				c.JSON(403, gin.H{
					"error": "Account banned",
					"code":  "ACCOUNT_BANNED",
				})
				c.Abort()
				return
			}
		}

		c.Set("uid", uid)

		if email, ok := token.Claims["email"].(string); ok {
			c.Set("email", email)
		}

		log.Printf("✅ User authenticated: %s", uid)
		c.Next()
	}
}
