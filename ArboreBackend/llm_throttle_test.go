package main

import (
	"context"
	"errors"
	"testing"
	"time"
)

// providerFactice compte ses appels et répond instantanément.
type providerFactice struct {
	rps    float64
	appels int
}

func (p *providerFactice) Name() string      { return "factice" }
func (p *providerFactice) Limits() LLMLimits { return LLMLimits{RequestsPerSecond: p.rps} }
func (p *providerFactice) Generate(ctx context.Context, req LLMRequest) (LLMResult, error) {
	p.appels++
	return LLMResult{Text: "ok"}, nil
}

// Un fournisseur sans débit déclaré ne doit pas être enveloppé du tout : pas
// d'indirection, donc pas de latence ajoutée au comportement actuel de Gemini.
func TestThrottled_SansDebitDeclareNenveloppePas(t *testing.T) {
	p := &providerFactice{rps: 0}
	if got := throttled(p); got != LLMProvider(p) {
		t.Fatalf("le fournisseur doit être renvoyé tel quel, obtenu %T", got)
	}
}

func TestThrottled_AvecDebitEnveloppeEtConserveNomEtLimites(t *testing.T) {
	p := &providerFactice{rps: 5}
	enveloppe := throttled(p)
	if _, ok := enveloppe.(*throttledProvider); !ok {
		t.Fatalf("décorateur attendu, obtenu %T", enveloppe)
	}
	if enveloppe.Name() != "factice" {
		t.Errorf("le nom doit traverser le décorateur, obtenu %q", enveloppe.Name())
	}
	if enveloppe.Limits().RequestsPerSecond != 5 {
		t.Errorf("les limites doivent traverser le décorateur")
	}
}

func TestThrottled_NilResteNil(t *testing.T) {
	if throttled(nil) != nil {
		t.Fatal("throttled(nil) doit rendre nil")
	}
}

// Le débit est réellement appliqué : à 20 req/s, quatre appels d'affilée
// prennent au moins trois intervalles (le premier jeton est disponible
// d'emblée, capacité 1).
func TestThrottled_LeDebitEstApplique(t *testing.T) {
	p := &providerFactice{rps: 20} // 50 ms entre deux jetons
	enveloppe := throttled(p)

	debut := time.Now()
	for i := 0; i < 4; i++ {
		if _, err := enveloppe.Generate(context.Background(), LLMRequest{}); err != nil {
			t.Fatalf("appel %d en erreur: %v", i, err)
		}
	}
	ecoule := time.Since(debut)

	const minimum = 3 * 50 * time.Millisecond
	if ecoule < minimum {
		t.Fatalf("4 appels à 20 req/s doivent prendre ≥ %s, obtenu %s", minimum, ecoule)
	}
	if p.appels != 4 {
		t.Fatalf("4 appels attendus, obtenu %d", p.appels)
	}
}

// Au-delà de l'attente maximale, on rend ErrLLMSurcharge SANS appeler le
// fournisseur : consommer un quota pour une réponse que personne n'attend plus
// serait le pire des deux mondes.
func TestThrottled_AuDelaDeLAttenteMaxRendSurchargeSansAppeler(t *testing.T) {
	p := &providerFactice{rps: 1}
	tp := &throttledProvider{
		inner:   p,
		limiter: throttled(p).(*throttledProvider).limiter,
		maxWait: 10 * time.Millisecond, // bien moins que la seconde entre deux jetons
	}

	// Le premier appel consomme le jeton disponible.
	if _, err := tp.Generate(context.Background(), LLMRequest{}); err != nil {
		t.Fatalf("premier appel en erreur: %v", err)
	}
	appelsApresPremier := p.appels

	_, err := tp.Generate(context.Background(), LLMRequest{})
	if !errors.Is(err, ErrLLMSurcharge) {
		t.Fatalf("ErrLLMSurcharge attendue, obtenu %v", err)
	}
	if p.appels != appelsApresPremier {
		t.Fatalf("le fournisseur ne doit pas être appelé quand la porte refuse (appels %d → %d)",
			appelsApresPremier, p.appels)
	}
}

// Un contexte annulé pendant l'attente rend la main tout de suite, et rend
// l'erreur du contexte — pas ErrLLMSurcharge : le client est parti, ce n'est
// pas une saturation.
func TestThrottled_ContexteAnnulePendantLAttente(t *testing.T) {
	p := &providerFactice{rps: 1}
	enveloppe := throttled(p)

	if _, err := enveloppe.Generate(context.Background(), LLMRequest{}); err != nil {
		t.Fatalf("premier appel en erreur: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	debut := time.Now()
	_, err := enveloppe.Generate(ctx, LLMRequest{})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("context.Canceled attendu, obtenu %v", err)
	}
	if ecoule := time.Since(debut); ecoule > time.Second {
		t.Fatalf("l'annulation doit rendre la main aussitôt, obtenu %s", ecoule)
	}
}

func TestAttenteMax_DefautEtSurcharge(t *testing.T) {
	t.Setenv("AI_THROTTLE_MAX_WAIT", "")
	if got := attenteMax(); got != defaultAttenteMax {
		t.Errorf("défaut %s attendu, obtenu %s", defaultAttenteMax, got)
	}
	t.Setenv("AI_THROTTLE_MAX_WAIT", "2s")
	if got := attenteMax(); got != 2*time.Second {
		t.Errorf("2s attendu, obtenu %s", got)
	}
	// Une valeur illisible ne doit pas empêcher de démarrer.
	t.Setenv("AI_THROTTLE_MAX_WAIT", "n'importe quoi")
	if got := attenteMax(); got != defaultAttenteMax {
		t.Errorf("repli sur le défaut attendu, obtenu %s", got)
	}
	// Une durée négative non plus.
	t.Setenv("AI_THROTTLE_MAX_WAIT", "-3s")
	if got := attenteMax(); got != defaultAttenteMax {
		t.Errorf("repli sur le défaut attendu pour une durée négative, obtenu %s", got)
	}
}

func TestDebitDeclare_DefautEtSurcharge(t *testing.T) {
	t.Setenv("TEST_RPS", "")
	if got := debitDeclare("TEST_RPS", 1.5); got != 1.5 {
		t.Errorf("défaut 1.5 attendu, obtenu %v", got)
	}
	t.Setenv("TEST_RPS", "12")
	if got := debitDeclare("TEST_RPS", 1.5); got != 12 {
		t.Errorf("12 attendu, obtenu %v", got)
	}
	t.Setenv("TEST_RPS", "-4")
	if got := debitDeclare("TEST_RPS", 1.5); got != 1.5 {
		t.Errorf("repli sur le défaut attendu pour une valeur négative, obtenu %v", got)
	}
	t.Setenv("TEST_RPS", "beaucoup")
	if got := debitDeclare("TEST_RPS", 1.5); got != 1.5 {
		t.Errorf("repli sur le défaut attendu pour une valeur illisible, obtenu %v", got)
	}
}

// Le palier gratuit de Mistral est à 1 req/s : c'est ce qui sature en premier,
// et le défaut ne doit pas dériver sans qu'on s'en aperçoive.
func TestMistralDeclareLeDebitDuPalierGratuit(t *testing.T) {
	t.Setenv("MISTRAL_RPS", "")
	if got := (&MistralProvider{}).Limits().RequestsPerSecond; got != defaultMistralRPS {
		t.Fatalf("%v req/s attendu, obtenu %v", defaultMistralRPS, got)
	}
}

// Gemini ne déclare rien : son comportement ne doit pas changer.
func TestGeminiNeDeclareAucunDebitParDefaut(t *testing.T) {
	t.Setenv("GEMINI_RPS", "")
	if got := (&GeminiProvider{}).Limits().RequestsPerSecond; got != 0 {
		t.Fatalf("0 attendu (aucun étranglement), obtenu %v", got)
	}
}
