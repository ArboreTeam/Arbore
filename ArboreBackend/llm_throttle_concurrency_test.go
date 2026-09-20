package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// --- Concurrence : la raison d'être de la porte -----------------------------
//
// Les limiteurs de middleware sont par utilisateur ; ils laissent passer dix
// clients simultanés chacun dans son droit. La porte est là pour ça, et elle ne
// vaut que si elle tient sous parallélisme — un test séquentiel ne le prouve
// pas.

// providerConcurrent enregistre l'instant de chaque appel et le parallélisme
// maximal observé à l'intérieur de Generate.
type providerConcurrent struct {
	rps       float64
	mu        sync.Mutex
	instants  []time.Time
	enCours   int32
	maxParall int32
}

func (p *providerConcurrent) Name() string      { return "concurrent" }
func (p *providerConcurrent) Limits() LLMLimits { return LLMLimits{RequestsPerSecond: p.rps} }
func (p *providerConcurrent) Generate(ctx context.Context, req LLMRequest) (LLMResult, error) {
	n := atomic.AddInt32(&p.enCours, 1)
	for {
		max := atomic.LoadInt32(&p.maxParall)
		if n <= max || atomic.CompareAndSwapInt32(&p.maxParall, max, n) {
			break
		}
	}
	p.mu.Lock()
	p.instants = append(p.instants, time.Now())
	p.mu.Unlock()
	time.Sleep(5 * time.Millisecond)
	atomic.AddInt32(&p.enCours, -1)
	return LLMResult{Text: "ok"}, nil
}

// Dix appelants simultanés ne doivent pas franchir la porte plus vite que le
// débit déclaré. C'est l'invariant que les limiteurs par utilisateur ne peuvent
// pas garantir.
func TestThrottled_DixAppelantsSimultanesRespectentLeDebitGlobal(t *testing.T) {
	const appelants = 10
	p := &providerConcurrent{rps: 50} // 20 ms entre deux jetons
	porte := throttled(p)

	debut := time.Now()
	var wg sync.WaitGroup
	for i := 0; i < appelants; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := porte.Generate(context.Background(), LLMRequest{}); err != nil {
				t.Errorf("appel en erreur: %v", err)
			}
		}()
	}
	wg.Wait()
	ecoule := time.Since(debut)

	if len(p.instants) != appelants {
		t.Fatalf("%d appels attendus, obtenu %d", appelants, len(p.instants))
	}
	// Le premier jeton est disponible d'emblée : il reste 9 intervalles.
	minimum := time.Duration(appelants-1) * 20 * time.Millisecond
	if ecoule < minimum {
		t.Fatalf("10 appels à 50 req/s doivent prendre ≥ %s, obtenu %s — "+
			"la porte ne sérialise pas sous parallélisme", minimum, ecoule)
	}
}

// Le débit tient quel que soit le nombre d'appelants : vingt clients ne doivent
// pas obtenir deux fois plus de débit que dix.
func TestThrottled_LeDebitNeDependPasDuNombreDAppelants(t *testing.T) {
	mesure := func(appelants int) time.Duration {
		p := &providerConcurrent{rps: 100} // 10 ms
		porte := throttled(p)
		debut := time.Now()
		var wg sync.WaitGroup
		for i := 0; i < appelants; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				_, _ = porte.Generate(context.Background(), LLMRequest{})
			}()
		}
		wg.Wait()
		return time.Since(debut)
	}

	dix := mesure(10)
	vingt := mesure(20)

	// Deux fois plus d'appelants ⇒ au moins ~deux fois plus de temps.
	if vingt < dix {
		t.Fatalf("20 appelants (%s) ne peuvent pas finir avant 10 (%s)", vingt, dix)
	}
	if vingt < 15*10*time.Millisecond {
		t.Fatalf("20 appels à 100 req/s doivent prendre ≥ 150 ms, obtenu %s", vingt)
	}
}

// Sous saturation, les appelants refusés le sont proprement : pas de panique,
// pas de blocage, et le fournisseur n'est jamais appelé plus que de raison.
func TestThrottled_SousSaturationLesRefusSontPropres(t *testing.T) {
	p := &providerConcurrent{rps: 1}
	porte := &throttledProvider{
		inner:   p,
		limiter: throttled(p).(*throttledProvider).limiter,
		maxWait: 30 * time.Millisecond,
	}

	const appelants = 20
	var refus, succes int32
	var wg sync.WaitGroup
	for i := 0; i < appelants; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := porte.Generate(context.Background(), LLMRequest{})
			switch {
			case err == nil:
				atomic.AddInt32(&succes, 1)
			case errors.Is(err, ErrLLMSurcharge):
				atomic.AddInt32(&refus, 1)
			default:
				t.Errorf("erreur inattendue: %v", err)
			}
		}()
	}
	wg.Wait()

	// Somme comparée en int : convertir la constante en int32 ferait râler gosec
	// sur un débordement qui ne peut pas se produire ici.
	if int(succes)+int(refus) != appelants {
		t.Fatalf("chaque appelant doit finir : %d succès + %d refus ≠ %d", succes, refus, appelants)
	}
	if refus == 0 {
		t.Fatal("à 1 req/s avec 30 ms d'attente, la majorité doit être refusée")
	}
	// Invariant central : le fournisseur n'a vu que les appels admis.
	if len(p.instants) != int(succes) {
		t.Fatalf("le fournisseur a vu %d appels pour %d admis", len(p.instants), succes)
	}
}

// --- initLLMProvider : le câblage réel --------------------------------------

func TestInitLLMProvider_GeminiNestPasEtrangle(t *testing.T) {
	prev := activeLLMProvider
	t.Cleanup(func() { activeLLMProvider = prev })

	t.Setenv("AI_PROVIDER", "gemini")
	t.Setenv("GEMINI_RPS", "")
	if err := initLLMProvider(); err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if _, enveloppe := activeLLMProvider.(*throttledProvider); enveloppe {
		t.Fatal("Gemini ne déclare aucun débit : il ne doit pas être enveloppé")
	}
	if providerName() != "gemini" {
		t.Errorf(`providerName() doit valoir "gemini", obtenu %q`, providerName())
	}
}

func TestInitLLMProvider_MistralEstEtrangle(t *testing.T) {
	prev := activeLLMProvider
	t.Cleanup(func() { activeLLMProvider = prev })

	t.Setenv("AI_PROVIDER", "mistral")
	t.Setenv("MISTRAL_RPS", "")
	if err := initLLMProvider(); err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if _, enveloppe := activeLLMProvider.(*throttledProvider); !enveloppe {
		t.Fatalf("Mistral déclare 1 req/s : il doit être enveloppé, obtenu %T", activeLLMProvider)
	}
	// Le nom doit traverser, sinon les journaux mentiraient sur le fournisseur.
	if providerName() != "mistral" {
		t.Errorf(`providerName() doit valoir "mistral", obtenu %q`, providerName())
	}
}

// Une valeur vide vaut Gemini — c'est ce qui maintient la production en place
// tant que personne ne bascule sciemment.
func TestInitLLMProvider_ValeurVideVautGemini(t *testing.T) {
	prev := activeLLMProvider
	t.Cleanup(func() { activeLLMProvider = prev })

	t.Setenv("AI_PROVIDER", "")
	if err := initLLMProvider(); err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if providerName() != "gemini" {
		t.Fatalf(`"" doit retenir gemini, obtenu %q`, providerName())
	}
}

// Un nom inconnu doit faire échouer le démarrage, pas retomber en silence sur
// un fournisseur que personne n'a demandé.
func TestInitLLMProvider_NomInconnuEchoue(t *testing.T) {
	prev := activeLLMProvider
	t.Cleanup(func() { activeLLMProvider = prev })

	t.Setenv("AI_PROVIDER", "openai")
	err := initLLMProvider()
	if err == nil {
		t.Fatal("un AI_PROVIDER inconnu doit faire échouer l'initialisation")
	}
	if !contientTous(err.Error(), "gemini", "mistral") {
		t.Errorf("le message doit énumérer les valeurs attendues, obtenu %q", err)
	}
}

func contientTous(s string, morceaux ...string) bool {
	for _, m := range morceaux {
		found := false
		for i := 0; i+len(m) <= len(s); i++ {
			if s[i:i+len(m)] == m {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}

// --- generateLLM / providerName sans fournisseur ----------------------------

func TestGenerateLLM_SansFournisseurConfigure(t *testing.T) {
	prev := activeLLMProvider
	t.Cleanup(func() { activeLLMProvider = prev })
	activeLLMProvider = nil

	if _, err := generateLLM(context.Background(), LLMRequest{}); err == nil {
		t.Fatal("erreur attendue sans fournisseur")
	}
	if providerName() != "none" {
		t.Errorf(`providerName() doit valoir "none", obtenu %q`, providerName())
	}
}

// --- Reprises HTTP de Mistral -----------------------------------------------

// Un 429 est retenté : sur le palier gratuit c'est un régime de charge normal,
// pas une panne.
func TestMistralPost_429EstRetenteePuisAboutit(t *testing.T) {
	var appels int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if atomic.AddInt32(&appels, 1) == 1 {
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(`{"message":"Rate limit exceeded"}`))
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(mistralChoiceResponse("enfin"))
	}))
	defer srv.Close()
	t.Setenv("MISTRAL_BASE_URL", srv.URL)

	p := &MistralProvider{apiKey: "k", model: "m", client: srv.Client()}
	res, err := p.Generate(context.Background(), LLMRequest{UserText: "x"})
	if err != nil {
		t.Fatalf("un 429 doit être retenté: %v", err)
	}
	if res.Text != "enfin" {
		t.Fatalf("texte inattendu: %q", res.Text)
	}
	if appels != 2 {
		t.Fatalf("2 appels attendus (429 puis succès), obtenu %d", appels)
	}
}

// Un 5xx aussi : l'indisponibilité passagère du fournisseur ne doit pas
// remonter jusqu'à l'utilisateur.
func TestMistralPost_5xxEstRetentee(t *testing.T) {
	var appels int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if atomic.AddInt32(&appels, 1) == 1 {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(mistralChoiceResponse("ok"))
	}))
	defer srv.Close()
	t.Setenv("MISTRAL_BASE_URL", srv.URL)

	p := &MistralProvider{apiKey: "k", model: "m", client: srv.Client()}
	if _, err := p.Generate(context.Background(), LLMRequest{UserText: "x"}); err != nil {
		t.Fatalf("un 502 doit être retenté: %v", err)
	}
	if appels != 2 {
		t.Fatalf("2 appels attendus, obtenu %d", appels)
	}
}

// L'attente entre deux tentatives respecte l'annulation : un client parti ne
// doit pas laisser une goroutine dormir neuf secondes.
func TestMistralPost_LAnnulationInterrompLAttenteEntreTentatives(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer srv.Close()
	t.Setenv("MISTRAL_BASE_URL", srv.URL)

	ctx, cancel := context.WithTimeout(context.Background(), 80*time.Millisecond)
	defer cancel()

	p := &MistralProvider{apiKey: "k", model: "m", client: srv.Client()}
	debut := time.Now()
	if _, err := p.Generate(ctx, LLMRequest{UserText: "x"}); err == nil {
		t.Fatal("erreur attendue")
	}
	// Sans respect du contexte, le premier backoff seul durerait 1 s.
	if ecoule := time.Since(debut); ecoule > 700*time.Millisecond {
		t.Fatalf("l'annulation doit couper l'attente, obtenu %s", ecoule)
	}
}

// Sans surcharge, l'appel vise bien l'API publique.
func TestMistralEndpoint_DefautEtSurcharge(t *testing.T) {
	t.Setenv("MISTRAL_BASE_URL", "")
	p := &MistralProvider{}
	if got := p.endpoint(); got != mistralChatURL {
		t.Errorf("URL publique attendue, obtenu %q", got)
	}
	t.Setenv("MISTRAL_BASE_URL", "http://localhost:1234")
	if got := p.endpoint(); got != "http://localhost:1234" {
		t.Errorf("surcharge ignorée, obtenu %q", got)
	}
}

// Une panne de transport (hôte injoignable) est retentée comme un 5xx, et
// l'annulation coupe l'attente : sans elle, les trois backoffs cumulés
// feraient dormir la goroutine quatorze secondes.
func TestMistralPost_PanneDeTransportRetenteePuisAnnulee(t *testing.T) {
	// Port fermé : la connexion échoue immédiatement, avant toute réponse.
	t.Setenv("MISTRAL_BASE_URL", "http://127.0.0.1:1")

	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Millisecond)
	defer cancel()

	p := &MistralProvider{apiKey: "k", model: "m", client: &http.Client{Timeout: time.Second}}
	debut := time.Now()
	_, err := p.Generate(ctx, LLMRequest{UserText: "x"})
	if err == nil {
		t.Fatal("erreur attendue sur un hôte injoignable")
	}
	if ecoule := time.Since(debut); ecoule > 800*time.Millisecond {
		t.Fatalf("l'annulation doit couper le backoff, obtenu %s", ecoule)
	}
}

// Une URL de base invalide échoue à la construction de la requête, sans
// tentative réseau ni reprise.
func TestMistralPost_URLInvalideEchoueSansReessai(t *testing.T) {
	t.Setenv("MISTRAL_BASE_URL", "http://\x7f invalide")

	p := &MistralProvider{apiKey: "k", model: "m", client: http.DefaultClient}
	if _, err := p.Generate(context.Background(), LLMRequest{UserText: "x"}); err == nil {
		t.Fatal("erreur attendue sur une URL invalide")
	}
}

// Une réponse tronquée (le serveur coupe la connexion en pleine lecture) est
// traitée comme une erreur de lecture, pas comme une réponse vide qu'on
// propagerait à l'utilisateur.
func TestMistralPost_ReponseTronqueeEstUneErreur(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "500")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[`))
		if f, ok := w.(http.Flusher); ok {
			f.Flush()
		}
		// La connexion se ferme ici : le corps annoncé n'arrivera jamais en entier.
	}))
	defer srv.Close()
	t.Setenv("MISTRAL_BASE_URL", srv.URL)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	p := &MistralProvider{apiKey: "k", model: "m", client: srv.Client()}
	if _, err := p.Generate(ctx, LLMRequest{UserText: "x"}); err == nil {
		t.Fatal("une réponse tronquée doit remonter une erreur")
	}
}

// --- Le modèle par défaut doit être un modèle réellement accordé -----------

// Régression du 2026-09-20 : le défaut était `mistral-small-latest`, un alias
// absent du catalogue de l'organisation. L'API ne répond pas « modèle
// inconnu » mais 429 avec `x-ratelimit-limit-req-minute: 0`, ce qui se lit
// comme un problème de compte. Seule la famille Ministral est accordée.
func TestMistral_LeModeleParDefautEstDeLaFamilleAccordee(t *testing.T) {
	const prefixeAccorde = "ministral-"
	if len(defaultMistralModel) < len(prefixeAccorde) ||
		defaultMistralModel[:len(prefixeAccorde)] != prefixeAccorde {
		t.Fatalf("le modèle par défaut doit être de la famille Ministral, seule accordée "+
			"sur ce plan — obtenu %q", defaultMistralModel)
	}
}

// Un modèle Labs annulerait l'opt-out d'entraînement, quel que soit le réglage
// de la console. Le défaut ne doit jamais en être un.
func TestMistral_LeModeleParDefautNestPasUnModeleLabs(t *testing.T) {
	const labs = "labs-"
	if len(defaultMistralModel) >= len(labs) && defaultMistralModel[:len(labs)] == labs {
		t.Fatalf("un modèle Labs accepte l'entraînement « regardless of opt-out settings » "+
			"— obtenu %q", defaultMistralModel)
	}
}

// Le débit déclaré doit rester cohérent avec celui du modèle par défaut.
// 188 req/min mesurées = 3,13 req/s ; on déclare 3,0 pour la marge.
func TestMistral_LeDebitDeclareCorrespondAuModeleParDefaut(t *testing.T) {
	if defaultMistralRPS <= 0 || defaultMistralRPS > 3.13 {
		t.Fatalf("le débit déclaré doit tenir dans les 3,13 req/s mesurées "+
			"pour %s — obtenu %v", defaultMistralModel, defaultMistralRPS)
	}
}
