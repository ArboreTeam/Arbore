package middleware

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestRequireAdmin(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, test := range []struct {
		name       string
		isAdmin    bool
		wantStatus int
	}{
		{name: "admin allowed", isAdmin: true, wantStatus: http.StatusOK},
		{name: "user forbidden", isAdmin: false, wantStatus: http.StatusForbidden},
	} {
		t.Run(test.name, func(t *testing.T) {
			router := gin.New()
			router.Use(func(c *gin.Context) {
				c.Set(adminContextKey, test.isAdmin)
				c.Next()
			})
			router.POST("/admin", RequireAdmin(), func(c *gin.Context) { c.Status(http.StatusOK) })
			w := httptest.NewRecorder()
			router.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/admin", nil))
			if w.Code != test.wantStatus {
				t.Fatalf("got %d, want %d", w.Code, test.wantStatus)
			}
		})
	}
}

func TestAdminSources(t *testing.T) {
	if !tokenHasAdminRole(map[string]interface{}{"admin": true}) {
		t.Fatal("admin custom claim should be accepted")
	}
	if !tokenHasAdminRole(map[string]interface{}{"role": "ADMIN"}) {
		t.Fatal("admin role claim should be accepted")
	}
	t.Setenv("ARBORE_ADMIN_UIDS", "first, second")
	if !isAdminUID("second") || isAdminUID("third") {
		t.Fatal("admin UID allow-list was not enforced")
	}
}

func TestWindowLimiterRejectsExcessRequests(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(func(c *gin.Context) { c.Set("uid", "user-1"); c.Next() })
	router.Use(NewWindowLimiter(2, time.Minute).Middleware())
	router.GET("/", func(c *gin.Context) { c.Status(http.StatusOK) })

	for requestNumber, want := range []int{http.StatusOK, http.StatusOK, http.StatusTooManyRequests} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/", nil))
		if w.Code != want {
			t.Fatalf("request %d got %d, want %d", requestNumber+1, w.Code, want)
		}
	}
}

// Non-régression de l'audit #338 constat 2 : un client qui forge X-Forwarded-For
// obtenait une clé de compteur différente à chaque requête, donc un quota infini.
func TestWindowLimiterIgnoresForgedForwardedFor(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(NewWindowLimiter(3, time.Minute).Middleware())
	router.GET("/", func(c *gin.Context) { c.Status(http.StatusOK) })

	// 20 requêtes du même client réel, chacune prétendant venir d'une autre IP.
	blocked := 0
	for i := 0; i < 20; i++ {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.RemoteAddr = "172.18.0.1:4242" // gateway Docker, identique pour tous
		req.Header.Set("X-Forwarded-For", fmt.Sprintf("203.0.113.%d", i))
		req.Header.Set("CF-Connecting-IP", "198.51.100.7") // vraie IP, posée par Cloudflare
		router.ServeHTTP(w, req)
		if w.Code == http.StatusTooManyRequests {
			blocked++
		}
	}

	if blocked != 17 {
		t.Fatalf("X-Forwarded-For forgé contourne le quota : %d/20 bloquées, attendu 17", blocked)
	}
}

// Sans en-tête de confiance, deux clients derrière la même gateway Docker ne
// doivent pas être distingués par un X-Forwarded-For qu'ils contrôlent.
func TestWindowLimiterFallsBackToSocketIP(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(NewWindowLimiter(2, time.Minute).Middleware())
	router.GET("/", func(c *gin.Context) { c.Status(http.StatusOK) })

	for requestNumber, want := range []int{http.StatusOK, http.StatusOK, http.StatusTooManyRequests} {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.RemoteAddr = "192.0.2.10:1111"
		req.Header.Set("X-Forwarded-For", fmt.Sprintf("203.0.113.%d", requestNumber))
		router.ServeHTTP(w, req)
		if w.Code != want {
			t.Fatalf("requête %d: got %d, want %d", requestNumber+1, w.Code, want)
		}
	}
}

// Un uid authentifié doit primer sur toute IP : c'est la clé la plus fiable.
func TestWindowLimiterPrefersAuthenticatedUID(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(func(c *gin.Context) { c.Set("uid", "user-1"); c.Next() })
	router.Use(NewWindowLimiter(1, time.Minute).Middleware())
	router.GET("/", func(c *gin.Context) { c.Status(http.StatusOK) })

	// Même uid, IP de confiance différente à chaque fois : le quota doit tenir.
	for requestNumber, want := range []int{http.StatusOK, http.StatusTooManyRequests} {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.Header.Set("CF-Connecting-IP", fmt.Sprintf("198.51.100.%d", requestNumber))
		router.ServeHTTP(w, req)
		if w.Code != want {
			t.Fatalf("requête %d: got %d, want %d", requestNumber+1, w.Code, want)
		}
	}
}

func TestTrustedClientIP(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, test := range []struct {
		name    string
		headers map[string]string
		remote  string
		want    string
	}{
		{
			name:    "CF-Connecting-IP prioritaire",
			headers: map[string]string{"CF-Connecting-IP": "198.51.100.7", "X-Real-IP": "192.0.2.5", "X-Forwarded-For": "203.0.113.1"},
			remote:  "172.18.0.1:1234",
			want:    "198.51.100.7",
		},
		{
			name:    "X-Real-IP en repli",
			headers: map[string]string{"X-Real-IP": "192.0.2.5", "X-Forwarded-For": "203.0.113.1"},
			remote:  "172.18.0.1:1234",
			want:    "192.0.2.5",
		},
		{
			name:    "X-Forwarded-For jamais utilise",
			headers: map[string]string{"X-Forwarded-For": "203.0.113.1"},
			remote:  "172.18.0.1:1234",
			want:    "172.18.0.1",
		},
		{
			name:    "en-tete de confiance vide ignore",
			headers: map[string]string{"X-Real-IP": "  "},
			remote:  "172.18.0.1:1234",
			want:    "172.18.0.1",
		},
		{
			name:    "valeur non-IP rejetee",
			headers: map[string]string{"CF-Connecting-IP": "not-an-ip; DROP TABLE"},
			remote:  "172.18.0.1:1234",
			want:    "172.18.0.1",
		},
		{
			name:    "IPv6 acceptee",
			headers: map[string]string{"CF-Connecting-IP": "2001:db8::1"},
			remote:  "172.18.0.1:1234",
			want:    "2001:db8::1",
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			var got string
			router := gin.New()
			router.GET("/", func(c *gin.Context) { got = TrustedClientIP(c) })

			req := httptest.NewRequest(http.MethodGet, "/", nil)
			req.RemoteAddr = test.remote
			for name, value := range test.headers {
				req.Header.Set(name, value)
			}
			router.ServeHTTP(httptest.NewRecorder(), req)

			if got != test.want {
				t.Fatalf("got %q, want %q", got, test.want)
			}
		})
	}
}

func TestMaxBodyBytes(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(MaxBodyBytes(4))
	router.POST("/", func(c *gin.Context) { c.Status(http.StatusOK) })

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/", strings.NewReader("12345"))
	router.ServeHTTP(w, req)
	if w.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("got %d, want %d", w.Code, http.StatusRequestEntityTooLarge)
	}
}
