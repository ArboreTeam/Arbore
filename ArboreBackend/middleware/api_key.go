// Package middleware provides HTTP middleware for the Arbore API.
package middleware

import (
	"crypto/subtle"
	"os"

	"github.com/gin-gonic/gin"
)

// DBSelectorKey is the gin.Context key under which APIKeyMiddleware stores
// the logical database target ("prod" or "test"). Handlers read this value
// to pick the right mongo.Database via the helper in main.go.
const DBSelectorKey = "arboreDB"

// Logical database selectors written to the gin.Context.
const (
	DBSelectorProd = "prod"
	DBSelectorTest = "test"
)

// APIKeyMiddleware validates the X-API-Key header against either:
//
//   - ARBORE_API_KEY      → context value DBSelectorKey = DBSelectorProd
//   - ARBORE_API_KEY_TEST → context value DBSelectorKey = DBSelectorTest
//
// Tests in the iOS target inject the test key during CI runs (cf. #159 v2),
// so the same backend process handles both prod traffic and the integration
// test suite without mutating prod data. ARBORE_API_KEY_TEST is optional —
// if unset, only the prod key is accepted.
func APIKeyMiddleware() gin.HandlerFunc {
	expectedKey := os.Getenv("ARBORE_API_KEY")
	if expectedKey == "" {
		panic("ARBORE_API_KEY environment variable not set")
	}
	testKey := os.Getenv("ARBORE_API_KEY_TEST")

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

		if subtle.ConstantTimeCompare([]byte(apiKey), []byte(expectedKey)) == 1 {
			c.Set(DBSelectorKey, DBSelectorProd)
			c.Next()
			return
		}

		if testKey != "" && subtle.ConstantTimeCompare([]byte(apiKey), []byte(testKey)) == 1 {
			c.Set(DBSelectorKey, DBSelectorTest)
			c.Next()
			return
		}

		c.JSON(401, gin.H{
			"error": "Invalid API key",
			"code":  "INVALID_API_KEY",
		})
		c.Abort()
	}
}
