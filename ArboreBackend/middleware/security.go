package middleware

import (
	"fmt"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

type windowEntry struct {
	started time.Time
	count   int
}

// WindowLimiter is a small per-instance limiter suitable for Arbore's current
// single backend instance. Create a distinct instance for each cost class
// (ordinary API, chat, diagnosis, generation) so their budgets stay isolated.
type WindowLimiter struct {
	mu          sync.Mutex
	limit       int
	window      time.Duration
	entries     map[string]windowEntry
	lastCleanup time.Time
}

func NewWindowLimiter(limit int, window time.Duration) *WindowLimiter {
	if limit <= 0 {
		panic("rate-limit must be positive")
	}
	if window <= 0 {
		panic("rate-limit window must be positive")
	}
	return &WindowLimiter{
		limit:       limit,
		window:      window,
		entries:     make(map[string]windowEntry),
		lastCleanup: time.Now(),
	}
}

func (l *WindowLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		now := time.Now()
		key := c.GetString("uid")
		if key == "" {
			key = c.ClientIP()
		}

		allowed, remaining, retryAfter := l.allow(key, now)
		c.Header("X-RateLimit-Limit", strconv.Itoa(l.limit))
		c.Header("X-RateLimit-Remaining", strconv.Itoa(remaining))
		if !allowed {
			seconds := int(retryAfter.Round(time.Second).Seconds())
			if seconds < 1 {
				seconds = 1
			}
			c.Header("Retry-After", strconv.Itoa(seconds))
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "Request quota exceeded",
				"code":  "RATE_LIMITED",
			})
			c.Abort()
			return
		}
		c.Next()
	}
}

func (l *WindowLimiter) allow(key string, now time.Time) (bool, int, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()

	if now.Sub(l.lastCleanup) >= l.window {
		for entryKey, entry := range l.entries {
			if now.Sub(entry.started) >= l.window {
				delete(l.entries, entryKey)
			}
		}
		l.lastCleanup = now
	}

	entry, exists := l.entries[key]
	if !exists || now.Sub(entry.started) >= l.window {
		l.entries[key] = windowEntry{started: now, count: 1}
		return true, l.limit - 1, 0
	}
	if entry.count >= l.limit {
		return false, 0, l.window - now.Sub(entry.started)
	}
	entry.count++
	l.entries[key] = entry
	return true, l.limit - entry.count, 0
}

// MaxBodyBytes rejects declared oversized requests and also wraps streaming or
// chunked bodies, preventing a client from bypassing Content-Length checks.
func MaxBodyBytes(limit int64) gin.HandlerFunc {
	if limit <= 0 {
		panic("body limit must be positive")
	}
	return func(c *gin.Context) {
		if c.Request.ContentLength > limit {
			c.JSON(http.StatusRequestEntityTooLarge, gin.H{
				"error": fmt.Sprintf("Request body too large (max %d bytes)", limit),
				"code":  "REQUEST_TOO_LARGE",
			})
			c.Abort()
			return
		}
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, limit)
		c.Next()
	}
}
