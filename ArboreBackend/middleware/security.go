package middleware

import (
	"fmt"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// Headers portant l'IP client réelle, par ordre de confiance décroissante.
//
// `CF-Connecting-IP` est écrasé par Cloudflare à chaque requête ; `X-Real-IP`
// est posé par nginx (`proxy_set_header X-Real-IP $http_cf_connecting_ip`),
// donc un client ne peut pas l'imposer. Les deux ne sont dignes de confiance
// que parce que l'origine est pare-feutée sur les plages Cloudflare : nginx est
// le seul chemin d'entrée.
//
// `X-Forwarded-For` est délibérément ABSENT de cette liste : nginx le construit
// avec `$proxy_add_x_forwarded_for`, qui *ajoute* à la valeur envoyée par le
// client au lieu de l'écraser — ses entrées de gauche sont donc contrôlées par
// l'attaquant, et gin les prend pour l'IP client (cf. audit #338, constat 2).
var trustedClientIPHeaders = []string{"CF-Connecting-IP", "X-Real-IP"}

// TrustedClientIP renvoie l'IP client la moins falsifiable disponible, ou une
// chaîne vide si aucune n'est exploitable. Seules des IP valides sont
// retournées : une valeur d'en-tête arbitraire ne doit jamais devenir une clé
// de compteur.
func TrustedClientIP(c *gin.Context) string {
	for _, header := range trustedClientIPHeaders {
		candidate := strings.TrimSpace(c.GetHeader(header))
		if candidate == "" {
			continue
		}
		if net.ParseIP(candidate) != nil {
			return candidate
		}
	}
	// Dernier recours : l'IP de la socket. En production c'est la gateway Docker
	// (identique pour tout le monde), donc volontairement le dernier choix — mais
	// c'est le bon comportement en local et dans les tests.
	if remote := c.RemoteIP(); net.ParseIP(remote) != nil {
		return remote
	}
	return ""
}

// rateLimitKey détermine le compteur auquel imputer la requête : l'utilisateur
// authentifié en priorité, sinon son IP réelle. Les requêtes dont on ne peut
// identifier ni l'un ni l'autre partagent un compteur unique plutôt que de
// passer sans limite.
func rateLimitKey(c *gin.Context) string {
	if uid := c.GetString("uid"); uid != "" {
		return "uid:" + uid
	}
	if ip := TrustedClientIP(c); ip != "" {
		return "ip:" + ip
	}
	return "unknown"
}

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
		allowed, remaining, retryAfter := l.allow(rateLimitKey(c), now)
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
