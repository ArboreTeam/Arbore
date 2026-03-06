// Package middleware provides authentication and authorization middleware for the Arbore backend
package middleware

import (
	"os"

	"github.com/gin-gonic/gin"
)

// APIKeyMiddleware validates the X-API-Key header against the ARBORE_API_KEY environment variable
func APIKeyMiddleware() gin.HandlerFunc {
	expectedKey := os.Getenv("ARBORE_API_KEY")

	if expectedKey == "" {
		panic("ARBORE_API_KEY environment variable not set")
	}

	return func(c *gin.Context) {
		apiKey := c.GetHeader("X-API-Key")

		if apiKey == "" {
			c.JSON(401, gin.H{
				"error": "API key required",
				"code":  "MISSING_API_KEY",
			})
			c.Abort()
			return
		}

		if apiKey != expectedKey {
			c.JSON(401, gin.H{
				"error": "Invalid API key",
				"code":  "INVALID_API_KEY",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}
