package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

// Implémentation Gemini de LLMProvider. Toute la traduction spécifique à l'API
// Google Gemini (payload systemInstruction/contents/inlineData, appel HTTP,
// extraction des candidats) est confinée ici.

const defaultGeminiModel = "gemini-2.5-flash"

// GeminiProvider parle à l'API Google Generative Language.
type GeminiProvider struct {
	apiKey string
	model  string
	client *http.Client
}

// newGeminiProvider lit la configuration depuis l'environnement. La clé peut
// être vide ici : Generate renvoie alors une erreur (comportement historique,
// 502 côté handler) plutôt que d'empêcher le démarrage du serveur.
func newGeminiProvider() *GeminiProvider {
	model := os.Getenv("GEMINI_MODEL")
	if model == "" {
		model = defaultGeminiModel
	}
	return &GeminiProvider{
		apiKey: os.Getenv("GEMINI_API_KEY"),
		model:  model,
		client: &http.Client{Timeout: 60 * time.Second},
	}
}

func (p *GeminiProvider) Name() string { return "gemini" }

// Generate traduit la requête neutre en payload Gemini, appelle l'API et
// extrait le texte de la réponse.
func (p *GeminiProvider) Generate(ctx context.Context, req LLMRequest) (LLMResult, error) {
	if p.apiKey == "" {
		return LLMResult{}, errors.New("GEMINI_API_KEY non configurée dans l'environnement")
	}
	respData, err := p.postGenerateContent(ctx, buildGeminiPayload(req))
	if err != nil {
		return LLMResult{}, err
	}
	return extractGeminiText(respData)
}

// buildGeminiPayload construit le corps `generateContent` à partir de la requête
// neutre : prompt système séparé, historique + tour courant, image inline.
func buildGeminiPayload(req LLMRequest) map[string]interface{} {
	contents := make([]map[string]interface{}, 0, len(req.History)+1)
	for _, m := range req.History {
		role := "model"
		if m.FromUser {
			role = "user"
		}
		contents = append(contents, map[string]interface{}{
			"role":  role,
			"parts": []map[string]interface{}{{"text": m.Text}},
		})
	}

	parts := []map[string]interface{}{{"text": req.UserText}}
	if req.ImageJPEGBase64 != "" {
		parts = append(parts, map[string]interface{}{
			"inlineData": map[string]interface{}{
				"mimeType": "image/jpeg",
				"data":     req.ImageJPEGBase64,
			},
		})
	}
	contents = append(contents, map[string]interface{}{"role": "user", "parts": parts})

	return map[string]interface{}{
		"systemInstruction": map[string]interface{}{
			"parts": []map[string]interface{}{{"text": req.SystemPrompt}},
		},
		"contents": contents,
	}
}

// extractGeminiText parse une réponse `generateContent`. Absence de candidat =
// réponse bloquée (sécurité/politique) → LLMResult{Blocked:true}.
func extractGeminiText(respData []byte) (LLMResult, error) {
	var gr map[string]interface{}
	if err := json.Unmarshal(respData, &gr); err != nil {
		return LLMResult{}, fmt.Errorf("réponse Gemini illisible: %w", err)
	}

	candidates, ok := gr["candidates"].([]interface{})
	if !ok || len(candidates) == 0 {
		return LLMResult{Blocked: true}, nil
	}

	firstCandidate, _ := candidates[0].(map[string]interface{})
	contentVal, _ := firstCandidate["content"].(map[string]interface{})
	partsVal, _ := contentVal["parts"].([]interface{})
	if len(partsVal) == 0 {
		return LLMResult{}, errors.New("réponse Gemini sans contenu")
	}

	firstPart, _ := partsVal[0].(map[string]interface{})
	text, _ := firstPart["text"].(string)
	return LLMResult{Text: text}, nil
}

// postGenerateContent effectue l'appel HTTP vers Gemini avec retries à backoff
// interruptible. La clé voyage dans l'en-tête `x-goog-api-key`, JAMAIS dans
// l'URL (une URL porteuse de la clé fuiterait dans les `*url.Error`).
func (p *GeminiProvider) postGenerateContent(ctx context.Context, payload map[string]interface{}) ([]byte, error) {
	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", p.model)

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("erreur de sérialisation de la requête Gemini: %w", err)
	}

	var respData []byte
	var lastErr error
	const maxAttempts = 4

	for attempt := 0; attempt < maxAttempts; {
		// Hôte codé en dur (generativelanguage.googleapis.com) : seul le nom du
		// modèle vient de l'env, donc pas de SSRF réel → gosec en faux positif.
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBuffer(bodyBytes)) //nolint:gosec // hôte constant Google, pas de SSRF
		if err != nil {
			return nil, fmt.Errorf("erreur lors de la création de la requête Gemini: %w", err)
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("x-goog-api-key", p.apiKey)

		resp, err := p.client.Do(req) //nolint:gosec // hôte constant Google, pas de SSRF
		if err != nil {
			lastErr = err
			attempt++
			if berr := backoffOrCancel(ctx, time.Duration(attempt*attempt)*time.Second); berr != nil {
				return nil, berr
			}
			continue
		}

		respData, err = io.ReadAll(io.LimitReader(resp.Body, 2<<20))
		closeErr := resp.Body.Close()
		if err != nil {
			lastErr = err
			attempt++
			continue
		}
		if closeErr != nil {
			return nil, fmt.Errorf("erreur lors de la fermeture de la réponse Gemini: %w", closeErr)
		}

		if resp.StatusCode != http.StatusOK {
			lastErr = fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(respData))
			if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= http.StatusInternalServerError {
				attempt++
				if berr := backoffOrCancel(ctx, time.Duration(attempt*attempt)*time.Second); berr != nil {
					return nil, berr
				}
				continue
			}
			return nil, lastErr
		}

		return respData, nil
	}

	return nil, fmt.Errorf("échec après %d tentatives de contact de l'API Gemini: %w", maxAttempts, lastErr)
}
