package middleware

import (
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
