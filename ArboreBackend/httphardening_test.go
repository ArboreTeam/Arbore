package main

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

// backoffOrCancel attend la durée demandée quand le contexte est valide.
func TestBackoffOrCancel_CompletesWhenNotCancelled(t *testing.T) {
	start := time.Now()
	if err := backoffOrCancel(context.Background(), 15*time.Millisecond); err != nil {
		t.Fatalf("attendu nil, obtenu %v", err)
	}
	if time.Since(start) < 10*time.Millisecond {
		t.Fatal("aurait dû patienter la durée demandée")
	}
}

// backoffOrCancel rend la main immédiatement avec l'erreur du contexte s'il est
// déjà annulé (client parti), sans attendre la durée.
func TestBackoffOrCancel_ReturnsOnCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	start := time.Now()
	if err := backoffOrCancel(ctx, 10*time.Second); err == nil {
		t.Fatal("attendu l'erreur du contexte annulé")
	}
	if time.Since(start) > time.Second {
		t.Fatal("n'aurait pas dû attendre la durée quand le contexte est annulé")
	}
}

func newBodyLimitEngine(maxBytes int64) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/x", limitRequestBody(maxBytes), func(c *gin.Context) {
		if _, err := io.ReadAll(c.Request.Body); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.Status(http.StatusOK)
	})
	return r
}

// Un corps plus gros que la limite fait échouer la lecture (le handler renvoie 400).
func TestLimitRequestBody_RejectsOversized(t *testing.T) {
	r := newBodyLimitEngine(10)
	req := httptest.NewRequest(http.MethodPost, "/x", bytes.NewReader(make([]byte, 100)))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("attendu 400 pour un corps trop gros, obtenu %d", w.Code)
	}
}

// Un corps dans la limite passe normalement.
func TestLimitRequestBody_AllowsWithinLimit(t *testing.T) {
	r := newBodyLimitEngine(1000)
	req := httptest.NewRequest(http.MethodPost, "/x", bytes.NewReader(make([]byte, 100)))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("attendu 200 pour un corps dans la limite, obtenu %d", w.Code)
	}
}
