package main

import (
	"context"
	"net/http"
	"time"
)

// Durcissement du serveur HTTP et des appels sortants (issue #303).
//
// Le rate limiting et le cap de corps des routes sont assurés par
// middleware/security.go (WindowLimiter + MaxBodyBytes, appliqués sur le groupe
// protégé). On garde ici les timeouts serveur et le backoff interruptible
// utilisé par le fournisseur LLM.

// backoffOrCancel attend d, sauf si le contexte est annulé entre-temps (client
// déconnecté ou timeout serveur). Évite de continuer à patienter puis à rappeler
// le fournisseur pour une requête que plus personne n'attend.
func backoffOrCancel(ctx context.Context, d time.Duration) error {
	select {
	case <-time.After(d):
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// newServer construit le http.Server avec des timeouts explicites. Sans eux, une
// connexion lente (Slowloris) ou inactive peut immobiliser des ressources
// indéfiniment. WriteTimeout est large car un appel LLM + ses retries peut durer
// plusieurs dizaines de secondes.
func newServer(addr string, h http.Handler) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           h,
		ReadHeaderTimeout: 15 * time.Second,  // anti-Slowloris
		ReadTimeout:       60 * time.Second,  // lecture du corps (cap via middleware.MaxBodyBytes)
		WriteTimeout:      300 * time.Second, // large : appels LLM + retries
		IdleTimeout:       120 * time.Second,
	}
}
