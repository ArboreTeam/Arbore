package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

// roles_test.go — issue #377.

// Le repli de NormalizeRole est la propriété la plus sensible du modèle : une
// valeur vide (tous les documents antérieurs à #377), inconnue ou mal casée doit
// donner `member`. Replier vers `guest` couperait l'accès des comptes existants ;
// replier vers `admin` serait une escalade de privilège silencieuse.
func TestNormalizeRoleFallsBackToMemberNeverGuestNorAdmin(t *testing.T) {
	for _, raw := range []string{"", "   ", "unknown", "MEMBRE", "root", "superuser"} {
		assert.Equal(t, RoleMember, NormalizeRole(raw),
			"une valeur non reconnue (%q) doit donner member", raw)
	}
}

func TestNormalizeRolePreservesKnownRoles(t *testing.T) {
	cases := map[string]string{
		"guest":   RoleGuest,
		"member":  RoleMember,
		"admin":   RoleAdmin,
		"owner":   RoleOwner,
		"support": RoleSupport,
		// La normalisation est insensible à la casse et aux espaces : un
		// document écrit à la main ne doit pas silencieusement rétrograder.
		"  ADMIN  ": RoleAdmin,
		"Guest":     RoleGuest,
	}
	for raw, expected := range cases {
		assert.Equal(t, expected, NormalizeRole(raw), "NormalizeRole(%q)", raw)
	}
}

// L'expiration est appliquée à la LECTURE : sans cela un abonnement échu
// resterait premium jusqu'au passage d'un job externe.
func TestNormalizeTierAppliesExpiryAtReadTime(t *testing.T) {
	now := time.Date(2026, 9, 1, 12, 0, 0, 0, time.UTC)
	past := now.Add(-time.Hour)
	future := now.Add(time.Hour)

	assert.Equal(t, TierFree, NormalizeTier(TierPremium, &past, now),
		"un abonnement expiré doit retomber en free sans attendre un webhook")
	assert.Equal(t, TierPremium, NormalizeTier(TierPremium, &future, now),
		"un abonnement en cours reste premium")
	assert.Equal(t, TierPremium, NormalizeTier(TierPremium, nil, now),
		"une absence de date de fin est un octroi permanent, pas une expiration")
}

func TestNormalizeTierFallsBackToFree(t *testing.T) {
	now := time.Now()
	for _, raw := range []string{"", "  ", "gold", "pro", "PREMIUMM"} {
		assert.Equal(t, TierFree, NormalizeTier(raw, nil, now),
			"une valeur non reconnue (%q) doit donner free", raw)
	}
	assert.Equal(t, TierPremium, NormalizeTier("  PREMIUM ", nil, now))
}

// Une session anonyme ne doit jamais franchir une route de compte, même si le
// reste de la chaîne l'a laissée passer.
func TestRequireAccountRejectsGuests(t *testing.T) {
	gin.SetMode(gin.TestMode)

	cases := []struct {
		role     string
		expected int
	}{
		{RoleGuest, http.StatusForbidden},
		{RoleMember, http.StatusOK},
		{RoleAdmin, http.StatusOK},
		// Les rôles réservés doivent passer : RequireAccount est formulé en
		// « tout sauf guest » précisément pour qu'un rôle ajouté plus tard ne
		// soit pas exclu par oubli.
		{RoleOwner, http.StatusOK},
		{RoleSupport, http.StatusOK},
	}

	for _, tc := range cases {
		router := gin.New()
		router.Use(func(c *gin.Context) {
			setAccessProfile(c, AccessProfile{Role: tc.role, Tier: TierFree})
			c.Next()
		})
		router.Use(RequireAccount())
		router.GET("/gardens", func(c *gin.Context) { c.Status(http.StatusOK) })

		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/gardens", nil))

		assert.Equal(t, tc.expected, w.Code, "rôle %s", tc.role)
		if tc.expected == http.StatusForbidden {
			assert.Contains(t, w.Body.String(), "ACCOUNT_REQUIRED")
		}
	}
}

// En l'absence de middleware d'authentification, le contexte ne porte aucun
// profil. Le défaut doit rester `member` : un défaut à `guest` transformerait
// une erreur de câblage en refus généralisé.
func TestRoleFromContextDefaultsToMember(t *testing.T) {
	gin.SetMode(gin.TestMode)
	c, _ := gin.CreateTestContext(httptest.NewRecorder())

	assert.Equal(t, RoleMember, RoleFromContext(c))
	assert.Equal(t, TierFree, TierFromContext(c))

	_, ok := AccessProfileFromContext(c)
	assert.False(t, ok, "aucun profil ne doit être signalé comme présent")
}

func TestIsPrivilegedRole(t *testing.T) {
	assert.True(t, IsPrivilegedRole(RoleAdmin))
	assert.True(t, IsPrivilegedRole(RoleOwner))
	assert.False(t, IsPrivilegedRole(RoleMember))
	assert.False(t, IsPrivilegedRole(RoleGuest))
	assert.False(t, IsPrivilegedRole(RoleSupport),
		"support est un accès en lecture, pas un accès d'administration")
}

// Chaque profil doit consommer SON budget : un invité ne doit jamais entamer
// celui d'un abonné, et inversement.
func TestTieredWindowLimiterIsolatesBudgetsPerProfile(t *testing.T) {
	gin.SetMode(gin.TestMode)
	limiter := NewTieredWindowLimiter(1, 2, 3, time.Minute)

	call := func(role, tier string) int {
		router := gin.New()
		router.Use(func(c *gin.Context) {
			c.Set("uid", "same-uid-for-every-call")
			setAccessProfile(c, AccessProfile{Role: role, Tier: tier})
			c.Next()
		})
		router.Use(limiter.Middleware())
		router.POST("/chat", func(c *gin.Context) { c.Status(http.StatusOK) })

		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/chat", nil))
		return w.Code
	}

	// Budget invité : 1 requête.
	assert.Equal(t, http.StatusOK, call(RoleGuest, TierFree))
	assert.Equal(t, http.StatusTooManyRequests, call(RoleGuest, TierFree))

	// Le même uid en member/free repart sur un budget distinct de 2.
	assert.Equal(t, http.StatusOK, call(RoleMember, TierFree))
	assert.Equal(t, http.StatusOK, call(RoleMember, TierFree))
	assert.Equal(t, http.StatusTooManyRequests, call(RoleMember, TierFree))

	// Et en premium, sur un troisième budget de 3.
	assert.Equal(t, http.StatusOK, call(RoleMember, TierPremium))
	assert.Equal(t, http.StatusOK, call(RoleMember, TierPremium))
	assert.Equal(t, http.StatusOK, call(RoleMember, TierPremium))
	assert.Equal(t, http.StatusTooManyRequests, call(RoleMember, TierPremium))
}

// Le rôle prime sur le tier : un invité n'a pas de document utilisateur, donc
// pas de tier réel. Un tier `premium` posé dans son contexte ne doit jamais lui
// ouvrir le budget d'un abonné.
func TestTieredWindowLimiterIgnoresTierForGuests(t *testing.T) {
	gin.SetMode(gin.TestMode)
	limiter := NewTieredWindowLimiter(1, 2, 3, time.Minute)

	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	setAccessProfile(c, AccessProfile{Role: RoleGuest, Tier: TierPremium})

	assert.Same(t, limiter.guest, limiter.limiterFor(c))
}
