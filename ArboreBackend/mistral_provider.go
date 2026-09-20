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

// Implémentation Mistral de LLMProvider (issues #553, #555).
//
// Pourquoi Mistral à côté de Gemini : c'est le seul fournisseur européen des
// candidats retenus, donc le seul qui supprime le transfert hors UE pour /chat
// et /diagnose. Le comparatif complet est dans
// docs/fr/operations/fournisseurs-llm.md.
//
// ⚠️ Le palier gratuit « Experiment » est opté-IN par défaut dans le programme
// d'amélioration de Mistral. Avant d'y envoyer la moindre photo d'utilisateur,
// désactiver « Anonymous improvement data » dans la console d'administration
// (menu Privacy). Ce n'est pas quelque chose que le code peut vérifier.
//
// L'API suit la forme Chat Completions : un seul tableau `messages` où le
// prompt système est un tour comme les autres, là où Gemini le sépare dans
// `systemInstruction`. Toute cette traduction reste confinée ici.

const (
	defaultMistralModel = "mistral-small-latest"
	mistralChatURL      = "https://api.mistral.ai/v1/chat/completions"
)

// MistralProvider parle à l'API Chat Completions de La Plateforme.
type MistralProvider struct {
	apiKey string
	model  string
	client *http.Client
}

// newMistralProvider lit la configuration depuis l'environnement. Comme pour
// Gemini, une clé vide n'empêche pas le démarrage : c'est Generate qui échoue,
// et le handler répond 502.
func newMistralProvider() *MistralProvider {
	model := os.Getenv("MISTRAL_MODEL")
	if model == "" {
		model = defaultMistralModel
	}
	return &MistralProvider{
		apiKey: secretFromFileOrEnv("MISTRAL_API_KEY"),
		model:  model,
		client: &http.Client{Timeout: 60 * time.Second},
	}
}

func (p *MistralProvider) Name() string { return "mistral" }

// Generate traduit la requête neutre, appelle l'API et extrait le texte.
func (p *MistralProvider) Generate(ctx context.Context, req LLMRequest) (LLMResult, error) {
	if p.apiKey == "" {
		return LLMResult{}, errors.New("MISTRAL_API_KEY non configurée dans l'environnement")
	}
	respData, err := p.postChatCompletions(ctx, buildMistralPayload(p.model, req))
	if err != nil {
		return LLMResult{}, err
	}
	return extractMistralText(respData)
}

// buildMistralPayload construit le corps `chat/completions`.
//
// Le tour courant porte l'image quand il y en a une. Sans image, `content` est
// une simple chaîne ; avec, c'est un tableau de parties, et l'image voyage en
// URI de données `data:image/jpeg;base64,…` sous une clé `url` — la forme
// qu'attend l'API, et non une chaîne nue.
func buildMistralPayload(model string, req LLMRequest) map[string]interface{} {
	messages := make([]map[string]interface{}, 0, len(req.History)+2)

	if req.SystemPrompt != "" {
		messages = append(messages, map[string]interface{}{
			"role":    "system",
			"content": req.SystemPrompt,
		})
	}

	for _, m := range req.History {
		role := "assistant"
		if m.FromUser {
			role = "user"
		}
		messages = append(messages, map[string]interface{}{
			"role":    role,
			"content": m.Text,
		})
	}

	current := map[string]interface{}{"role": "user"}
	if req.ImageJPEGBase64 == "" {
		current["content"] = req.UserText
	} else {
		current["content"] = []map[string]interface{}{
			{"type": "text", "text": req.UserText},
			{
				"type": "image_url",
				"image_url": map[string]interface{}{
					"url": "data:image/jpeg;base64," + req.ImageJPEGBase64,
				},
			},
		}
	}
	messages = append(messages, current)

	return map[string]interface{}{
		"model":    model,
		"messages": messages,
	}
}

// extractMistralText parse une réponse `chat/completions`.
//
// Absence de choix = réponse écartée par le fournisseur, traitée comme un
// blocage — même convention que Gemini, pour que les handlers n'aient pas à
// distinguer les deux.
func extractMistralText(respData []byte) (LLMResult, error) {
	var mr struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
			FinishReason string `json:"finish_reason"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respData, &mr); err != nil {
		return LLMResult{}, fmt.Errorf("réponse Mistral illisible: %w", err)
	}

	if len(mr.Choices) == 0 {
		return LLMResult{Blocked: true}, nil
	}
	// Un filtrage côté fournisseur rend un choix sans texte : c'est un blocage,
	// pas une réponse vide à propager.
	if mr.Choices[0].Message.Content == "" {
		return LLMResult{Blocked: true}, nil
	}
	return LLMResult{Text: mr.Choices[0].Message.Content}, nil
}

// postChatCompletions effectue l'appel HTTP avec les mêmes retries à backoff
// interruptible que Gemini. La clé voyage dans l'en-tête Authorization, jamais
// dans l'URL : une URL porteuse de la clé fuiterait dans les *url.Error.
func (p *MistralProvider) postChatCompletions(ctx context.Context, payload map[string]interface{}) ([]byte, error) {
	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("erreur de sérialisation de la requête Mistral: %w", err)
	}

	var lastErr error
	const maxAttempts = 4

	for attempt := 0; attempt < maxAttempts; {
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.endpoint(), bytes.NewBuffer(bodyBytes))
		if err != nil {
			return nil, fmt.Errorf("erreur lors de la création de la requête Mistral: %w", err)
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Accept", "application/json")
		req.Header.Set("Authorization", "Bearer "+p.apiKey)

		resp, err := p.client.Do(req)
		if err != nil {
			lastErr = err
			attempt++
			if berr := backoffOrCancel(ctx, time.Duration(attempt*attempt)*time.Second); berr != nil {
				return nil, berr
			}
			continue
		}

		respData, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
		closeErr := resp.Body.Close()
		if err != nil {
			lastErr = err
			attempt++
			continue
		}
		if closeErr != nil {
			return nil, fmt.Errorf("erreur lors de la fermeture de la réponse Mistral: %w", closeErr)
		}

		if resp.StatusCode != http.StatusOK {
			lastErr = fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(respData))
			// 429 et 5xx se retentent ; le reste est définitif.
			//
			// Le palier gratuit est plafonné à environ une requête par seconde,
			// donc un 429 y est un régime normal sous charge, pas un incident.
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

	return nil, fmt.Errorf("appel Mistral en échec après %d tentatives: %w", maxAttempts, lastErr)
}

// endpoint permet aux tests de viser un serveur local. Vide = API publique.
func (p *MistralProvider) endpoint() string {
	if override := os.Getenv("MISTRAL_BASE_URL"); override != "" {
		return override
	}
	return mistralChatURL
}
