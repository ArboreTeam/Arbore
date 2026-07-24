package main

import (
	"context"
	"testing"
	"time"
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
