package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
)

// Abstraction du fournisseur d'IA conversationnelle/vision (issue #319).
//
// Objectif : couplage faible / cohésion forte. Les handlers (/chat, /diagnose)
// manipulent des types NEUTRES (prompt système, historique, message, image) et
// une interface stable `LLMProvider` ; ils ignorent tout du fournisseur concret.
// Changer de fournisseur (Gemini, Mistral, …) = ajouter une implémentation de
// `LLMProvider`, sans toucher aux handlers.

// LLMMessage est un tour de conversation, indépendant du fournisseur.
type LLMMessage struct {
	FromUser bool // true = utilisateur, false = assistant/modèle
	Text     string
}

// LLMRequest est une requête de génération indépendante du fournisseur.
type LLMRequest struct {
	SystemPrompt    string       // consignes (séparées du contenu utilisateur)
	History         []LLMMessage // tours précédents
	UserText        string       // message courant de l'utilisateur
	ImageJPEGBase64 string       // image jointe (JPEG base64), "" si aucune
}

// LLMResult est la réponse, indépendante du fournisseur.
type LLMResult struct {
	Text    string // texte produit par le modèle
	Blocked bool   // true si le fournisseur a bloqué la réponse (sécurité/politique)
}

// LLMProvider abstrait un modèle de chat/vision derrière une interface stable.
type LLMProvider interface {
	// Name identifie le fournisseur (télémétrie, logs).
	Name() string
	// Generate produit une réponse à partir d'une requête neutre.
	Generate(ctx context.Context, req LLMRequest) (LLMResult, error)
}

// activeLLMProvider est le fournisseur en service. Posé par initLLMProvider() au
// démarrage ; les tests l'injectent directement.
var activeLLMProvider LLMProvider

// initLLMProvider sélectionne le fournisseur selon AI_PROVIDER (défaut : gemini)
// et le pose dans activeLLMProvider. Appelé une fois au démarrage.
func initLLMProvider() error {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("AI_PROVIDER"))) {
	case "", "gemini":
		activeLLMProvider = newGeminiProvider()
	// case "mistral":
	//     activeLLMProvider = newMistralProvider()
	default:
		return fmt.Errorf("AI_PROVIDER inconnu: %q (attendu: gemini)", os.Getenv("AI_PROVIDER"))
	}
	return nil
}

// generateLLM appelle le fournisseur actif. Filet de sécurité si initLLMProvider
// n'a pas été appelé (ne devrait pas arriver en prod : main() l'initialise).
func generateLLM(ctx context.Context, req LLMRequest) (LLMResult, error) {
	if activeLLMProvider == nil {
		return LLMResult{}, errors.New("aucun fournisseur d'IA configuré")
	}
	return activeLLMProvider.Generate(ctx, req)
}

// providerName renvoie le nom du fournisseur actif (pour les logs).
func providerName() string {
	if activeLLMProvider == nil {
		return "none"
	}
	return activeLLMProvider.Name()
}
