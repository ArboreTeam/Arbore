package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	"golang.org/x/time/rate"
)

// Étranglement du fournisseur d'IA (issue #553).
//
// Les limiteurs de `middleware` sont posés PAR UTILISATEUR : ils répondent à une
// question d'équité — un seul utilisateur ne doit pas tout prendre. Ils ne
// peuvent pas, par construction, protéger le quota du fournisseur : dix
// utilisateurs chacun sagement sous sa limite personnelle produisent ensemble
// bien plus d'une requête par seconde.
//
// D'où cette porte GLOBALE, qui répond à l'autre question : tenons-nous le
// contrat du fournisseur ? Les deux coexistent, aucune ne remplace l'autre.
//
// Forme retenue : un décorateur. `LLMProvider` garde une seule raison de
// changer — l'API du fournisseur — et l'étranglement s'applique automatiquement
// à tout fournisseur ajouté ensuite, sans qu'il ait une ligne à écrire.
//
// ⚠️ La porte est globale PAR INSTANCE. Il n'y a qu'un backend aujourd'hui (le
// commentaire de middleware.WindowLimiter fait déjà cette hypothèse), mais le
// jour où une seconde instance tourne, le débit réel double silencieusement et
// le fournisseur refuse. Ce n'est pas une limite à découvrir en incident.

// ErrLLMSurcharge signale que la porte n'a pas pu admettre la requête dans le
// délai imparti. Ce n'est PAS une panne : les handlers doivent la distinguer
// d'une erreur de fournisseur et répondre 429 plutôt que 502.
var ErrLLMSurcharge = errors.New("service d'IA saturé, réessayer plus tard")

// defaultAttenteMax borne l'attente devant la porte. Quelques secondes sont
// acceptables ici parce qu'un appel LLM en prend déjà plusieurs — ce qui ne
// serait pas vrai sur une route ordinaire.
const defaultAttenteMax = 5 * time.Second

// throttledProvider enveloppe un fournisseur d'une porte à débit constant.
type throttledProvider struct {
	inner   LLMProvider
	limiter *rate.Limiter
	maxWait time.Duration
}

// throttled enveloppe le fournisseur si, et seulement si, il déclare un débit.
// Un fournisseur qui rend RequestsPerSecond = 0 est renvoyé tel quel : aucune
// indirection, aucune latence ajoutée.
func throttled(p LLMProvider) LLMProvider {
	if p == nil {
		return nil
	}
	debit := p.Limits().RequestsPerSecond
	if debit <= 0 {
		return p
	}

	// Capacité 1 : on lisse le débit au lieu d'autoriser une rafale qui se
	// ferait refuser d'un coup en face.
	limiter := rate.NewLimiter(rate.Limit(debit), 1)
	log.Printf("🚦 Étranglement du fournisseur %s : %.3g requête/s, attente max %s",
		p.Name(), debit, attenteMax())

	return &throttledProvider{inner: p, limiter: limiter, maxWait: attenteMax()}
}

// attenteMax lit AI_THROTTLE_MAX_WAIT (une durée Go, ex. « 3s »). Valeur
// illisible ou négative : on retombe sur la valeur par défaut plutôt que de
// refuser de démarrer.
func attenteMax() time.Duration {
	brut := os.Getenv("AI_THROTTLE_MAX_WAIT")
	if brut == "" {
		return defaultAttenteMax
	}
	d, err := time.ParseDuration(brut)
	if err != nil || d <= 0 {
		log.Printf("⚠️ AI_THROTTLE_MAX_WAIT illisible (%q), valeur par défaut %s", brut, defaultAttenteMax)
		return defaultAttenteMax
	}
	return d
}

func (t *throttledProvider) Name() string { return t.inner.Name() }

func (t *throttledProvider) Limits() LLMLimits { return t.inner.Limits() }

// Generate attend son tour, puis délègue.
//
// L'attente est bornée deux fois : par `maxWait`, et par le contexte de la
// requête HTTP. Dans les deux cas, AUCUN appel réseau n'est émis — refuser tôt
// vaut mieux que consommer un quota pour une réponse que personne n'attend
// plus.
func (t *throttledProvider) Generate(ctx context.Context, req LLMRequest) (LLMResult, error) {
	attente, cancel := context.WithTimeout(ctx, t.maxWait)
	defer cancel()

	if err := t.limiter.Wait(attente); err != nil {
		// Le contexte appelant a été annulé (client parti) : le dire tel quel.
		if ctx.Err() != nil {
			return LLMResult{}, ctx.Err()
		}
		// Sinon c'est notre propre délai qui a expiré : la porte est saturée.
		return LLMResult{}, fmt.Errorf("%w (attente > %s)", ErrLLMSurcharge, t.maxWait)
	}
	return t.inner.Generate(ctx, req)
}

// debitDeclare lit une surcharge de débit propre au fournisseur, en requêtes
// par seconde. Permet de passer d'un palier gratuit à un palier payant sans
// recompiler.
func debitDeclare(variable string, defaut float64) float64 {
	brut := os.Getenv(variable)
	if brut == "" {
		return defaut
	}
	v, err := strconv.ParseFloat(brut, 64)
	if err != nil || v < 0 {
		log.Printf("⚠️ %s illisible (%q), valeur par défaut %.3g req/s", variable, brut, defaut)
		return defaut
	}
	return v
}
