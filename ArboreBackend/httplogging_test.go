package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

// httplogging_test.go — issue #385.
//
// L'invariant : aucune adresse IP complète ne doit atteindre les journaux.

func TestMaskIPKeepsOnlyTheNetworkPrefix(t *testing.T) {
	cases := map[string]string{
		// IPv4 : les trois premiers octets, le dernier masqué.
		"92.184.105.42": "92.184.105.x",
		"8.8.8.8":       "8.8.8.x",
		"127.0.0.1":     "127.0.0.x",
		"172.18.0.7":    "172.18.0.x",
		// IPv6 : préfixe /48.
		"2a01:e0a:1b2:c3d4::1": "2a01:e0a:1b2:x",
		"::1":                  "0:0:0:x",
		// IPv4 exprimée en IPv6 mappée : traitée comme de l'IPv4.
		"::ffff:92.184.105.42": "92.184.105.x",
	}

	for raw, expected := range cases {
		assert.Equal(t, expected, maskIP(raw), "maskIP(%q)", raw)
	}
}

// Une valeur non parsable vient forcément d'un en-tête manipulable : elle ne
// doit pas être recopiée telle quelle dans les journaux.
func TestMaskIPRejectsNonAddresses(t *testing.T) {
	for _, raw := range []string{"", "   ", "pas-une-ip", "1.2.3", "<script>", "999.999.999.999"} {
		assert.Equal(t, "-", maskIP(raw), "maskIP(%q) doit être neutralisé", raw)
	}
}

// Le test qui compte vraiment : la ligne de journal produite ne contient jamais
// l'adresse complète.
func TestLogFormatterNeverEmitsAFullIP(t *testing.T) {
	full := "92.184.105.42"
	line := privacyPreservingLogFormatter(ginLogParams(full, "/gardens"))

	assert.NotContains(t, line, full,
		"l'adresse complète ne doit jamais apparaître dans une ligne de journal")
	assert.Contains(t, line, "92.184.105.x")
	assert.Contains(t, line, "/gardens")
}

func TestLogFormatterHandlesIPv6(t *testing.T) {
	full := "2a01:e0a:1b2:c3d4::1"
	line := privacyPreservingLogFormatter(ginLogParams(full, "/plants"))

	assert.NotContains(t, line, "c3d4", "le préfixe /48 ne doit pas laisser filtrer le sous-réseau")
	assert.Contains(t, line, "2a01:e0a:1b2:x")
}

// ginLogParams construit un jeu de paramètres de log minimal.
func ginLogParams(clientIP, path string) gin.LogFormatterParams {
	return gin.LogFormatterParams{
		TimeStamp:  time.Date(2026, 9, 2, 10, 0, 0, 0, time.UTC),
		StatusCode: http.StatusOK,
		Latency:    5 * time.Millisecond,
		ClientIP:   clientIP,
		Method:     http.MethodGet,
		Path:       path,
	}
}

// ─── #388 — /health exclu du journal d'accès ────────────────────────────────

// Mesuré en prod : 95 % des lignes du journal étaient des healthchecks. Les
// exclure préserve la profondeur d'historique pour le trafic qui a une valeur
// d'analyse.
func TestAccessLogSkipsHealthButNothingElse(t *testing.T) {
	assert.Contains(t, accessLogSkippedPaths, "/health")
	assert.Len(t, accessLogSkippedPaths, 1,
		"n'exclure que le healthcheck : toute autre route exclue serait un angle mort d'analyse")
}

// Vérifie le comportement réel du routeur, pas seulement la constante : une
// requête sur /health ne doit produire aucune ligne, une requête ordinaire si.
func TestRouterEngineOmitsHealthFromAccessLog(t *testing.T) {
	gin.SetMode(gin.TestMode)

	var logged bytes.Buffer
	previous := gin.DefaultWriter
	gin.DefaultWriter = &logged
	defer func() { gin.DefaultWriter = previous }()

	engine := newRouterEngine()
	engine.GET("/health", func(c *gin.Context) { c.Status(http.StatusOK) })
	engine.GET("/plants", func(c *gin.Context) { c.Status(http.StatusOK) })

	engine.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/health", nil))
	assert.Empty(t, logged.String(), "/health ne doit produire aucune ligne de journal d'accès")

	engine.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/plants", nil))
	assert.Contains(t, logged.String(), "/plants",
		"le trafic ordinaire doit rester journalisé")
}
