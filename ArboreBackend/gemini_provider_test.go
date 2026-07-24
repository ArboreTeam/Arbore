package main

import (
	"encoding/json"
	"testing"
)

// geminiCandidateResponse fabrique une réponse generateContent minimale.
func geminiCandidateResponse(text string) []byte {
	resp := map[string]interface{}{
		"candidates": []interface{}{
			map[string]interface{}{
				"content": map[string]interface{}{
					"parts": []interface{}{
						map[string]interface{}{"text": text},
					},
				},
			},
		},
	}
	b, _ := json.Marshal(resp)
	return b
}

func TestBuildGeminiPayload_SystemHistoryImage(t *testing.T) {
	req := LLMRequest{
		SystemPrompt:    "SYS",
		History:         []LLMMessage{{FromUser: true, Text: "salut"}, {FromUser: false, Text: "bonjour"}},
		UserText:        "et maintenant ?",
		ImageJPEGBase64: "AAAA",
	}
	payload := buildGeminiPayload(req)

	si, _ := payload["systemInstruction"].(map[string]interface{})
	siParts, _ := si["parts"].([]map[string]interface{})
	if len(siParts) == 0 || siParts[0]["text"] != "SYS" {
		t.Fatalf("systemInstruction incorrect: %v", payload["systemInstruction"])
	}

	contents, _ := payload["contents"].([]map[string]interface{})
	if len(contents) != 3 { // 2 historique + 1 tour courant
		t.Fatalf("attendu 3 tours, obtenu %d", len(contents))
	}
	if contents[0]["role"] != "user" || contents[1]["role"] != "model" || contents[2]["role"] != "user" {
		t.Fatalf("rôles inattendus: %v %v %v", contents[0]["role"], contents[1]["role"], contents[2]["role"])
	}
	lastParts, _ := contents[2]["parts"].([]map[string]interface{})
	if len(lastParts) != 2 { // texte + image
		t.Fatalf("tour courant attendu avec 2 parts (texte+image), obtenu %d", len(lastParts))
	}
	if _, ok := lastParts[1]["inlineData"]; !ok {
		t.Fatal("image inline absente du tour courant")
	}
}

func TestBuildGeminiPayload_NoImage(t *testing.T) {
	payload := buildGeminiPayload(LLMRequest{SystemPrompt: "S", UserText: "hi"})
	contents, _ := payload["contents"].([]map[string]interface{})
	if len(contents) != 1 {
		t.Fatalf("attendu 1 tour, obtenu %d", len(contents))
	}
	parts, _ := contents[0]["parts"].([]map[string]interface{})
	if len(parts) != 1 { // pas d'image
		t.Fatalf("sans image, attendu 1 part, obtenu %d", len(parts))
	}
}

func TestExtractGeminiText_OK(t *testing.T) {
	res, err := extractGeminiText(geminiCandidateResponse("réponse du modèle"))
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if res.Blocked {
		t.Fatal("ne devrait pas être bloqué")
	}
	if res.Text != "réponse du modèle" {
		t.Fatalf("texte inattendu: %q", res.Text)
	}
}

func TestExtractGeminiText_NoCandidatesIsBlocked(t *testing.T) {
	res, err := extractGeminiText([]byte(`{"candidates":[]}`))
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if !res.Blocked {
		t.Fatal("absence de candidat devrait être Blocked=true")
	}
}

func TestExtractGeminiText_InvalidJSON(t *testing.T) {
	if _, err := extractGeminiText([]byte(`{invalid`)); err == nil {
		t.Fatal("JSON invalide devrait renvoyer une erreur")
	}
}
