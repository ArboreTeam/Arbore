package main

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// Durcissement des proxies Gemini et du serveur HTTP (issue #303).

// maxGeminiBodyBytes borne la taille du corps JSON accepté par /chat et
// /diagnose. Les deux routes reçoivent une image encodée en base64 dans le
// JSON ; 16 Mo laissent passer une photo de téléphone tout en empêchant qu'un
// client fasse gonfler la RAM avec un corps arbitrairement gros.
const maxGeminiBodyBytes int64 = 16 << 20 // 16 Mo

// limitRequestBody place le corps de la requête derrière un http.MaxBytesReader :
// toute lecture au-delà de maxBytes échoue, ce qui borne la mémoire consommée
// par le parsing du corps (le handler renvoie alors 400).
func limitRequestBody(maxBytes int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBytes)
		c.Next()
	}
}

// backoffOrCancel attend d, sauf si le contexte est annulé entre-temps (client
// déconnecté ou timeout serveur). Évite de continuer à patienter puis à rappeler
// Gemini pour une requête que plus personne n'attend — et donc de payer l'appel.
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
// indéfiniment. WriteTimeout est large car un appel Gemini + ses retries peut
// durer plusieurs dizaines de secondes.
func newServer(addr string, h http.Handler) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           h,
		ReadHeaderTimeout: 15 * time.Second,  // anti-Slowloris
		ReadTimeout:       60 * time.Second,  // lecture du corps (aussi bornée par MaxBytesReader)
		WriteTimeout:      300 * time.Second, // large : appels Gemini + retries
		IdleTimeout:       120 * time.Second,
	}
}
