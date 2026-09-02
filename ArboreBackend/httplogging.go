package main

import (
	"fmt"
	"net"
	"time"

	"github.com/gin-gonic/gin"
)

// httplogging.go — journalisation HTTP à identifiabilité réduite (issue #385).
//
// `gin.Default()` embarque le logger par défaut, qui écrit `ClientIP()` sur
// stdout. Comme `hardenClientIPResolution` fixe `TrustedPlatform = "X-Real-IP"`,
// cette valeur est l'adresse IP RÉELLE de l'utilisateur final pour tout trafic
// passant par nginx — donc une donnée personnelle au sens du RGPD (CJUE Breyer,
// C-582/14), écrite dans les journaux Docker.
//
// On garde la valeur de diagnostic d'une IP (distinguer les appelants, repérer
// une source d'erreurs) en n'en journalisant que le préfixe réseau. Le rate
// limiting, lui, continue d'utiliser l'IP complète mais uniquement EN MÉMOIRE,
// dans un compteur purgé à l'expiration de la fenêtre : rien n'en est persisté.

// maskIP réduit une adresse IP à son préfixe réseau.
//
//	IPv4 → les trois premiers octets  (92.184.105.42       → 92.184.105.x)
//	IPv6 → le préfixe /48             (2a01:e0a:1b2:c3::1  → 2a01:e0a:1b2:x)
//
// Le /48 IPv6 est l'équivalent usuel du /24 IPv4 : c'est en général le bloc
// alloué à un abonné, donc le même compromis entre utilité et identifiabilité.
//
// Une valeur non parsable est remplacée par "-" plutôt que journalisée telle
// quelle : une chaîne arbitraire venue d'un en-tête n'a rien à faire dans les
// journaux.
func maskIP(raw string) string {
	parsed := net.ParseIP(raw)
	if parsed == nil {
		return "-"
	}
	if v4 := parsed.To4(); v4 != nil {
		return fmt.Sprintf("%d.%d.%d.x", v4[0], v4[1], v4[2])
	}
	v6 := parsed.To16()
	if v6 == nil {
		return "-"
	}
	return fmt.Sprintf("%x:%x:%x:x",
		int(v6[0])<<8|int(v6[1]),
		int(v6[2])<<8|int(v6[3]),
		int(v6[4])<<8|int(v6[5]),
	)
}

// privacyPreservingLogFormatter reproduit le format lisible de gin, avec l'IP
// tronquée. Volontairement proche de l'original pour ne pas casser les habitudes
// de lecture ni un éventuel parsing existant.
func privacyPreservingLogFormatter(p gin.LogFormatterParams) string {
	return fmt.Sprintf("[GIN] %s | %3d | %13v | %15s | %-7s %#v\n%s",
		p.TimeStamp.Format(time.RFC3339),
		p.StatusCode,
		p.Latency,
		maskIP(p.ClientIP),
		p.Method,
		p.Path,
		p.ErrorMessage,
	)
}

// accessLogSkippedPaths liste les routes exclues du journal d'accès (issue #388).
//
// Mesuré en production le 2026-09-02 : `/health` représentait 233 des 244
// lignes du journal, soit 95 %. Le healthcheck Docker interroge la route en
// continu, ce qui noie le trafic réel — les 429 du rate limiter, les 5xx — dans
// un bruit sans valeur d'analyse.
//
// À taille de fenêtre de rotation égale, cette exclusion multiplie par ~20 la
// profondeur d'historique réellement exploitable.
//
// Seul le journal d'ACCÈS est concerné : `Recovery()` et les erreurs
// applicatives continuent d'écrire sur stdout quelle que soit la route.
var accessLogSkippedPaths = []string{"/health"}

// newRouterEngine remplace `gin.Default()`.
//
// `gin.Default()` = `gin.New()` + `Logger()` + `Recovery()`. On reconstruit la
// même chose en substituant au logger par défaut celui qui masque l'IP ;
// `Recovery()` est conservé tel quel — le retirer transformerait n'importe quel
// panic de handler en connexion coupée sans réponse.
func newRouterEngine() *gin.Engine {
	engine := gin.New()
	engine.Use(gin.LoggerWithConfig(gin.LoggerConfig{
		Formatter: privacyPreservingLogFormatter,
		SkipPaths: accessLogSkippedPaths,
	}))
	engine.Use(gin.Recovery())
	return engine
}
