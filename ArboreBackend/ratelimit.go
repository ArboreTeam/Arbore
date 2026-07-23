package main

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/time/rate"
)

// userRateLimiter maintient un token-bucket par utilisateur (uid Firebase) pour
// une route donnée. Objectif : empêcher qu'un compte authentifié ne boucle les
// proxies Gemini (/chat, /diagnose) et ne génère un coût illimité (issue #303).
//
// Limites en mémoire process : suffisant tant qu'il n'y a qu'une instance backend.
// Note : la map croît d'une entrée par uid vu ; acceptable à l'échelle de la beta.
// Un éviction des buckets inactifs pourra être ajoutée si le volume grossit.
type userRateLimiter struct {
	mu      sync.Mutex
	buckets map[string]*rate.Limiter
	r       rate.Limit
	burst   int
}

func newUserRateLimiter(r rate.Limit, burst int) *userRateLimiter {
	return &userRateLimiter{buckets: make(map[string]*rate.Limiter), r: r, burst: burst}
}

func (u *userRateLimiter) limiterFor(uid string) *rate.Limiter {
	u.mu.Lock()
	defer u.mu.Unlock()
	l, ok := u.buckets[uid]
	if !ok {
		l = rate.NewLimiter(u.r, u.burst)
		u.buckets[uid] = l
	}
	return l
}

// middleware renvoie un handler Gin qui limite par uid (posé par
// FirebaseAuthMiddleware). À utiliser uniquement sur des routes du groupe
// protégé, où l'uid est garanti présent.
func (u *userRateLimiter) middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		uid := c.GetString("uid")
		if uid == "" {
			// Filet de sécurité : ne devrait pas arriver dans le groupe protégé.
			uid = "ip:" + c.ClientIP()
		}
		if !u.limiterFor(uid).Allow() {
			c.Header("Retry-After", "60")
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "Trop de requêtes. Réessaie dans un instant.",
				"code":  "RATE_LIMITED",
			})
			return
		}
		c.Next()
	}
}

// Limiteurs des proxies Gemini. Valeurs de première passe (par utilisateur) :
// assez larges pour un usage normal, assez strictes pour borner le coût Gemini
// et bloquer un client qui boucle. À ajuster selon l'usage réel.
var (
	// Chat : ~30 requêtes/heure, avec une petite rafale pour une conversation fluide.
	chatRateLimiter = newUserRateLimiter(rate.Every(time.Hour/30), 10)
	// Diagnostic photo (plus coûteux) : ~15 requêtes/heure.
	diagnoseRateLimiter = newUserRateLimiter(rate.Every(time.Hour/15), 5)
)
