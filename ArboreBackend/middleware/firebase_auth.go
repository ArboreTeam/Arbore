package middleware

import (
	"context"
	"log"
	"os"
	"strings"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"github.com/gin-gonic/gin"
	"google.golang.org/api/option"
)

var firebaseAuth *auth.Client
var CheckUserBannedFunc func(string) (bool, error)

func InitFirebase() error {
	serviceAccountPath := os.Getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
	if serviceAccountPath == "" {
		log.Println("⚠️  FIREBASE_SERVICE_ACCOUNT_PATH non défini, auth Firebase désactivée")
		return nil
	}

	opt := option.WithCredentialsFile(serviceAccountPath)
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
