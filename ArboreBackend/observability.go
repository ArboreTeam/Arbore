package main

// Sentry côté backend (#388).
//
// Avant ce fichier, les panics interceptés par `gin.Recovery()` et les réponses
// 5xx partaient sur stdout et NULLE PART AILLEURS : pas d'agrégation, pas de
// déduplication, pas d'alerte. Un panic un dimanche à 3 h du matin n'était
// découvrable que si quelqu'un pensait à lire `docker logs` — et seulement dans
// la fenêtre de rotation, trois fichiers de 10 Mo (#386).
//
// Le relevé du 2026-09-08 mesurait ce trou : zéro erreur dans les trois projets
// Sentry d'Arbore sur 90 jours. L'absence de données ÉTAIT le symptôme.

import (
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	sentrygin "github.com/getsentry/sentry-go/gin"

	sentry "github.com/getsentry/sentry-go"
	"github.com/gin-gonic/gin"
)

// sentryEnabled retient si le SDK a réellement démarré. Les middlewares ne sont
// montés que dans ce cas : sans DSN, aucun coût par requête.
var sentryEnabled bool

// sentryFlushTimeout borne l'attente à l'arrêt. Sentry envoie en arrière-plan ;
// sans flush, les événements produits juste avant l'extinction sont perdus. Deux
// secondes suffisent largement et ne retardent pas un redéploiement.
const sentryFlushTimeout = 2 * time.Second

// initSentry démarre le SDK si un DSN est fourni, et NE FAIT RIEN sinon.
//
// Ce comportement est délibéré et aligné sur iOS (`SentryManager.isConfigured`)
// et sur le web (`enabled: !!dsn`) : l'absence de secret ne doit jamais empêcher
// le backend de démarrer. Un contributeur sans accès aux secrets, et la CI,
// lancent le serveur à l'identique.
func initSentry() {
	dsn := strings.TrimSpace(os.Getenv("SENTRY_DSN"))
	if dsn == "" {
		log.Printf("ℹ️  Sentry désactivé (SENTRY_DSN vide) — erreurs sur stdout uniquement")
		return
	}

	err := sentry.Init(sentry.ClientOptions{
		Dsn: dsn,

		// L'environnement est fourni explicitement, jamais déduit. Le web s'en
		// est passé et le résultat est que prod et dev y remontent tous deux
		// sous l'étiquette `production`, indistinguables (#469). On ne refait
		// pas cette erreur ici.
		Environment: envOrDefault("SENTRY_ENVIRONMENT", "unknown"),

		// Le commit déployé, celui-là même qu'expose /health (#341) : injecté au
		// link via -ldflags, pas lu dans l'environnement. Permet de rattacher une
		// erreur à une version précise plutôt qu'à « la prod ».
		Release: buildCommit,

		// FAUX, et ça doit le rester. `true` joindrait l'adresse IP complète et
		// les en-têtes de requête aux événements. Le journal d'accès tronque
		// justement l'IP en /24 depuis #385 (donnée personnelle, CJUE Breyer
		// C-582/14) : envoyer l'IP entière à un tiers annulerait cette mesure.
		SendDefaultPII: false,

		// Pas d'échantillonnage des performances pour l'instant. Le besoin est
		// de voir les erreurs, pas de mesurer des latences — et le web montre
		// qu'un tracing mal filtré se remplit surtout de bruit (#469).
		EnableTracing: false,
	})
	if err != nil {
		// Volontairement NON fatal. Sentry est de l'observabilité : son échec ne
		// doit jamais empêcher le service de rendre son service. C'est aussi la
		// règle appliquée aux deux autres SDK.
		log.Printf("⚠️  Sentry n'a pas démarré (%v) — erreurs sur stdout uniquement", err)
		return
	}

	sentryEnabled = true
	log.Printf("🛰️  Sentry actif (environnement %q)", envOrDefault("SENTRY_ENVIRONMENT", "unknown"))
}

// flushSentry vide la file d'envoi. À appeler en `defer` depuis main().
//
// ⚠️ Un `defer` ne suffit PAS à couvrir les échecs de démarrage : `log.Fatalf`
// appelle `os.Exit`, qui n'exécute aucun defer. D'où `fatalf` ci-dessous.
func flushSentry() {
	if sentryEnabled {
		sentry.Flush(sentryFlushTimeout)
	}
}

// fatalf remplace `log.Fatalf` pour les échecs de DÉMARRAGE : il signale
// l'erreur à Sentry, attend l'envoi, puis quitte.
//
// La distinction compte. Un backend qui refuse de démarrer — Mongo injoignable,
// Firebase mal configuré — est le cas le plus grave et le plus silencieux : le
// conteneur boucle en redémarrage, aucune requête n'arrive, donc le middleware
// ne capture rien. Sans capture explicite ici, Sentry resterait muet
// précisément quand le service est totalement indisponible.
//
// L'attente de flush est bornée par `sentryFlushTimeout` : si Sentry est
// injoignable, le processus quitte quand même, avec au plus deux secondes de
// retard sur la boucle de redémarrage.
func fatalf(format string, args ...any) {
	err := fmt.Errorf(format, args...)
	if sentryEnabled {
		sentry.CaptureException(err)
		sentry.Flush(sentryFlushTimeout)
	}
	log.Fatal(err.Error())
}

// useSentryMiddleware monte la capture sur le routeur, si et seulement si le SDK
// tourne.
//
// `Repanic: true` est essentiel : sentrygin capture le panic puis le RELANCE.
// C'est `gin.Recovery()`, enregistré AVANT et donc gestionnaire extérieur, qui
// le rattrape et répond 500. Sans `Repanic`, Sentry avalerait le panic et le
// client verrait une connexion coupée au lieu d'une erreur propre.
func useSentryMiddleware(engine *gin.Engine) {
	if !sentryEnabled {
		return
	}
	engine.Use(sentrygin.New(sentrygin.Options{Repanic: true}))
	engine.Use(captureServerErrors())
}

// captureServerErrors remonte les réponses 5xx, que sentrygin ne voit pas — il
// ne capture que les panics.
//
// Le besoin est réel et mesurable : le code compte 40 réponses 500 explicites
// pour seulement 2 appels à `c.Error(...)`. Ne remonter que les erreurs
// déclarées couvrirait donc 5 % des cas.
//
// Pourquoi c'est sans doublon avec sentrygin, malgré les apparences : un panic
// remonte la pile et fait SAUTER tout ce qui suit `c.Next()`. Ce code ne
// s'exécute donc jamais pour un 500 issu d'un panic — celui-là est capturé par
// sentrygin puis converti en 500 par Recovery, bien plus haut. Les deux
// mécanismes se partagent naturellement le terrain : panics d'un côté, 5xx
// délibérés de l'autre.
func captureServerErrors() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Next()

		if c.Writer.Status() < 500 {
			return
		}
		hub := sentrygin.GetHubFromContext(c)
		if hub == nil {
			return
		}

		// Les erreurs déclarées quand il y en a : elles portent la cause réelle.
		// Sinon, un événement synthétique — moins riche, mais il situe la route
		// et le statut, ce qui vaut infiniment mieux que le silence.
		if len(c.Errors) > 0 {
			for _, e := range c.Errors {
				hub.CaptureException(e.Err)
			}
			return
		}
		hub.CaptureException(fmt.Errorf("HTTP %d sur %s %s",
			c.Writer.Status(), c.Request.Method, c.FullPath()))
	}
}
