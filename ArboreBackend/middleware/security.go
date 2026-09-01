package middleware

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"sort"
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

const (
	// Cadence de purge, indépendante de la fenêtre. L'implémentation d'origine
	// purgeait « une fois par fenêtre » : avec une fenêtre de 24 h (quotas
	// journaliers), une entrée expirée pouvait rester en mémoire jusqu'à 48 h
	// (audit #338 constat 10).
	limiterCleanupInterval = time.Minute

	// Plafond du nombre de compteurs suivis simultanément. Au-delà, les entrées
	// les plus anciennes sont évincées.
	//
	// Compromis assumé : évincer une entrée rend son quota à zéro, donc offre du
	// crédit gratuit. On préfère cela à une croissance mémoire non bornée — un
	// flot de clés distinctes ne doit pas pouvoir faire enfler le processus. Le
	// plafond est large : à l'échelle actuelle (quelques dizaines d'utilisateurs)
	// il ne se déclenche jamais, et son franchissement est journalisé.
	limiterMaxEntries = 50_000
)

// WindowLimiter is a small per-instance limiter suitable for Arbore's current
// single backend instance. Create a distinct instance for each cost class
// (ordinary API, chat, diagnosis, generation) so their budgets stay isolated.
type WindowLimiter struct {
	mu              sync.Mutex
	limit           int
	window          time.Duration
	entries         map[string]windowEntry
	lastCleanup     time.Time
	cleanupInterval time.Duration
	maxEntries      int
}

func NewWindowLimiter(limit int, window time.Duration) *WindowLimiter {
	if limit <= 0 {
		panic("rate-limit must be positive")
	}
	if window <= 0 {
		panic("rate-limit window must be positive")
	}
	// Purger plus souvent que la fenêtre n'a pas de sens : rien n'expire avant.
	cleanupInterval := limiterCleanupInterval
	if window < cleanupInterval {
		cleanupInterval = window
	}
	return &WindowLimiter{
		limit:           limit,
		window:          window,
		entries:         make(map[string]windowEntry),
		lastCleanup:     time.Now(),
		cleanupInterval: cleanupInterval,
		maxEntries:      limiterMaxEntries,
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

	if now.Sub(l.lastCleanup) >= l.cleanupInterval {
		l.purgeExpired(now)
		l.lastCleanup = now
	}

	entry, exists := l.entries[key]
	if !exists || now.Sub(entry.started) >= l.window {
		if !exists {
			l.makeRoomFor(now)
		}
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

// purgeExpired supprime les compteurs dont la fenêtre est écoulée.
// L'appelant détient déjà le verrou.
func (l *WindowLimiter) purgeExpired(now time.Time) {
	for key, entry := range l.entries {
		if now.Sub(entry.started) >= l.window {
			delete(l.entries, key)
		}
	}
}

// makeRoomFor garantit qu'une nouvelle clé peut être insérée sans dépasser le
// plafond. On tente d'abord une purge des entrées expirées ; si cela ne suffit
// pas, les compteurs les plus anciens sont évincés jusqu'à 90 % du plafond —
// viser en dessous du plafond évite de recommencer à chaque requête suivante.
// L'appelant détient déjà le verrou.
func (l *WindowLimiter) makeRoomFor(now time.Time) {
	if len(l.entries) < l.maxEntries {
		return
	}
	l.purgeExpired(now)
	l.lastCleanup = now
	if len(l.entries) < l.maxEntries {
		return
	}

	target := l.maxEntries * 9 / 10
	keys := make([]string, 0, len(l.entries))
	for key := range l.entries {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		return l.entries[keys[i]].started.Before(l.entries[keys[j]].started)
	})

	evicted := 0
	for _, key := range keys {
		if len(l.entries) <= target {
			break
		}
		delete(l.entries, key)
		evicted++
	}
	// Journalisé car ce n'est pas censé arriver à l'échelle actuelle : si ça
	// arrive, c'est soit une croissance réelle, soit un flot de clés distinctes.
	log.Printf("⚠️  rate limiter: plafond de %d compteurs atteint, %d entrée(s) la/les plus ancienne(s) évincée(s)",
		l.maxEntries, evicted)
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

// TieredWindowLimiter applique un budget distinct selon le profil d'accès de
// l'appelant (issue #377).
//
// Motivation : les routes qui appellent Gemini coûtent de l'argent à chaque
// requête. Moduler leur quota selon le niveau d'abonnement est l'usage le plus
// direct de `tier` — bien plus que le verrouillage de styles de jardin.
//
// Chaque classe possède son propre WindowLimiter, donc son propre compteur.
// Conséquence assumée : un utilisateur qui passe de free à premium au milieu
// d'une fenêtre repart d'un budget premium neuf. Le sens de l'erreur est
// favorable au client qui vient de payer, et le cas est rare par nature.
type TieredWindowLimiter struct {
	guest   *WindowLimiter
	free    *WindowLimiter
	premium *WindowLimiter
}

// NewTieredWindowLimiter construit les trois budgets d'une même fenêtre.
// Les limites doivent être croissantes (guest <= free <= premium) ; ce n'est pas
// imposé, mais l'inverse n'aurait pas de sens métier.
func NewTieredWindowLimiter(guestLimit, freeLimit, premiumLimit int, window time.Duration) *TieredWindowLimiter {
	return &TieredWindowLimiter{
		guest:   NewWindowLimiter(guestLimit, window),
		free:    NewWindowLimiter(freeLimit, window),
		premium: NewWindowLimiter(premiumLimit, window),
	}
}

// limiterFor choisit le budget applicable à la requête.
//
// Le rôle prime sur le tier : un invité n'a pas de document utilisateur, donc
// pas de tier réel, et ne doit jamais bénéficier d'un budget de compte payant.
func (t *TieredWindowLimiter) limiterFor(c *gin.Context) *WindowLimiter {
	if RoleFromContext(c) == RoleGuest {
		return t.guest
	}
	if TierFromContext(c) == TierPremium {
		return t.premium
	}
	return t.free
}

// Middleware applique le budget correspondant au profil de l'appelant.
func (t *TieredWindowLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		t.limiterFor(c).Middleware()(c)
	}
}
