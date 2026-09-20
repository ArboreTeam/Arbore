package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// mistralChoiceResponse fabrique une réponse chat/completions minimale.
func mistralChoiceResponse(text string) []byte {
	resp := map[string]interface{}{
		"choices": []interface{}{
			map[string]interface{}{
				"message":       map[string]interface{}{"content": text},
				"finish_reason": "stop",
			},
		},
	}
	b, _ := json.Marshal(resp)
	return b
}

// Le prompt système devient un tour `system` en tête, là où Gemini le sépare
// dans `systemInstruction`. C'est toute la différence de forme entre les deux.
func TestBuildMistralPayload_SystemPuisHistoriquePuisTourCourant(t *testing.T) {
	payload := buildMistralPayload("m", LLMRequest{
		SystemPrompt: "SYS",
		History: []LLMMessage{
			{FromUser: true, Text: "salut"},
			{FromUser: false, Text: "bonjour"},
		},
		UserText: "et maintenant ?",
	})

	messages, _ := payload["messages"].([]map[string]interface{})
	if len(messages) != 4 {
		t.Fatalf("4 messages attendus (système + 2 historique + courant), obtenu %d", len(messages))
	}

	attendu := []struct{ role, content string }{
		{"system", "SYS"},
		{"user", "salut"},
		{"assistant", "bonjour"},
		{"user", "et maintenant ?"},
	}
	for i, a := range attendu {
		if messages[i]["role"] != a.role {
			t.Errorf("message %d : rôle %q attendu, obtenu %q", i, a.role, messages[i]["role"])
		}
		if messages[i]["content"] != a.content {
			t.Errorf("message %d : contenu %q attendu, obtenu %v", i, a.content, messages[i]["content"])
		}
	}
}

// Un tour d'assistant doit porter le rôle "assistant" : Gemini dit "model", et
// reprendre ce mot ici ferait rejeter la requête.
func TestBuildMistralPayload_LAssistantNestPasAppeleModel(t *testing.T) {
	payload := buildMistralPayload("m", LLMRequest{
		History: []LLMMessage{{FromUser: false, Text: "réponse"}},
	})
	messages, _ := payload["messages"].([]map[string]interface{})
	if messages[0]["role"] != "assistant" {
		t.Fatalf(`rôle "assistant" attendu, obtenu %q`, messages[0]["role"])
	}
}

// Sans image, `content` reste une chaîne : l'envelopper inutilement dans un
// tableau de parties coûte des tokens et complique la lecture côté fournisseur.
func TestBuildMistralPayload_SansImageLeContenuResteUneChaine(t *testing.T) {
	payload := buildMistralPayload("m", LLMRequest{UserText: "bonjour"})
	messages, _ := payload["messages"].([]map[string]interface{})
	if _, estChaine := messages[len(messages)-1]["content"].(string); !estChaine {
		t.Fatalf("contenu chaîne attendu, obtenu %T", messages[len(messages)-1]["content"])
	}
}

// La forme attendue par l'API : `image_url` est un OBJET portant une clé `url`,
// et l'image voyage en URI de données. Une chaîne nue à la place de l'objet est
// l'erreur classique de portage depuis d'autres fournisseurs.
func TestBuildMistralPayload_LImageEstUneURIDeDonneesSousUneCleURL(t *testing.T) {
	payload := buildMistralPayload("m", LLMRequest{
		UserText:        "diagnostique",
		ImageJPEGBase64: "QUJD",
	})

	messages, _ := payload["messages"].([]map[string]interface{})
	parts, ok := messages[len(messages)-1]["content"].([]map[string]interface{})
	if !ok {
		t.Fatalf("tableau de parties attendu avec une image, obtenu %T", messages[len(messages)-1]["content"])
	}
	if len(parts) != 2 {
		t.Fatalf("2 parties attendues (texte + image), obtenu %d", len(parts))
	}
	if parts[0]["type"] != "text" || parts[0]["text"] != "diagnostique" {
		t.Errorf("partie texte incorrecte : %v", parts[0])
	}
	if parts[1]["type"] != "image_url" {
		t.Errorf(`type "image_url" attendu, obtenu %v`, parts[1]["type"])
	}

	img, ok := parts[1]["image_url"].(map[string]interface{})
	if !ok {
		t.Fatalf("image_url doit être un objet, obtenu %T", parts[1]["image_url"])
	}
	url, _ := img["url"].(string)
	if url != "data:image/jpeg;base64,QUJD" {
		t.Fatalf("URI de données attendue, obtenu %q", url)
	}
}

func TestExtractMistralText_ReponseNormale(t *testing.T) {
	res, err := extractMistralText(mistralChoiceResponse("bonjour"))
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if res.Text != "bonjour" || res.Blocked {
		t.Fatalf("résultat inattendu: %+v", res)
	}
}

// Aucun choix, ou un choix vide : le fournisseur a écarté la réponse. On rend
// Blocked plutôt qu'un texte vide, pour que les handlers gardent une seule
// convention quel que soit le fournisseur.
func TestExtractMistralText_SansChoixOuChoixVideEstUnBlocage(t *testing.T) {
	for nom, corps := range map[string]string{
		"aucun choix": `{"choices":[]}`,
		"choix vide":  `{"choices":[{"message":{"content":""}}]}`,
	} {
		t.Run(nom, func(t *testing.T) {
			res, err := extractMistralText([]byte(corps))
			if err != nil {
				t.Fatalf("erreur inattendue: %v", err)
			}
			if !res.Blocked {
				t.Fatalf("blocage attendu, obtenu %+v", res)
			}
		})
	}
}

func TestExtractMistralText_JSONInvalide(t *testing.T) {
	if _, err := extractMistralText([]byte("pas du json")); err == nil {
		t.Fatal("erreur attendue sur un corps illisible")
	}
}

// Une clé absente ne doit pas partir en appel réseau.
func TestMistralGenerate_SansCleEchoueAvantTouteRequete(t *testing.T) {
	p := &MistralProvider{model: "m", client: http.DefaultClient}
	if _, err := p.Generate(context.Background(), LLMRequest{UserText: "x"}); err == nil {
		t.Fatal("erreur attendue sans MISTRAL_API_KEY")
	}
}

// La clé doit voyager dans l'en-tête Authorization, jamais dans l'URL : une URL
// porteuse de la clé se retrouverait dans les *url.Error, donc dans les
// journaux.
func TestMistralGenerate_LaCleVoyageDansLEnTete(t *testing.T) {
	var vuAuth, vuURL string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		vuAuth = r.Header.Get("Authorization")
		vuURL = r.URL.String()
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(mistralChoiceResponse("ok"))
	}))
	defer srv.Close()
	t.Setenv("MISTRAL_BASE_URL", srv.URL)

	p := &MistralProvider{apiKey: "secret-clef", model: "m", client: srv.Client()}
	res, err := p.Generate(context.Background(), LLMRequest{UserText: "salut"})
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if res.Text != "ok" {
		t.Fatalf("texte inattendu: %q", res.Text)
	}
	if vuAuth != "Bearer secret-clef" {
		t.Errorf("en-tête Authorization attendu, obtenu %q", vuAuth)
	}
	if strings.Contains(vuURL, "secret-clef") {
		t.Errorf("la clé ne doit jamais apparaître dans l'URL: %q", vuURL)
	}
}

// Un 4xx définitif ne doit pas être retenté quatre fois.
func TestMistralGenerate_UneErreurDefinitiveNestPasRetentee(t *testing.T) {
	appels := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		appels++
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"modèle inconnu"}`))
	}))
	defer srv.Close()
	t.Setenv("MISTRAL_BASE_URL", srv.URL)

	p := &MistralProvider{apiKey: "k", model: "m", client: srv.Client()}
	if _, err := p.Generate(context.Background(), LLMRequest{UserText: "x"}); err == nil {
		t.Fatal("erreur attendue sur un 400")
	}
	if appels != 1 {
		t.Fatalf("1 appel attendu sur une erreur définitive, obtenu %d", appels)
	}
}

func TestMistralProviderName(t *testing.T) {
	if (&MistralProvider{}).Name() != "mistral" {
		t.Fatal(`Name() doit valoir "mistral"`)
	}
}

// Le modèle par défaut doit rester un modèle VISION : /diagnose envoie une
// image, et un modèle texte seul y répondrait par une erreur à chaque appel.
func TestNewMistralProvider_ModeleParDefautEtSurcharge(t *testing.T) {
	t.Setenv("MISTRAL_MODEL", "")
	if p := newMistralProvider(); p.model != defaultMistralModel {
		t.Fatalf("modèle par défaut attendu %q, obtenu %q", defaultMistralModel, p.model)
	}
	t.Setenv("MISTRAL_MODEL", "mistral-medium-latest")
	if p := newMistralProvider(); p.model != "mistral-medium-latest" {
		t.Fatalf("surcharge par MISTRAL_MODEL ignorée, obtenu %q", p.model)
	}
}
