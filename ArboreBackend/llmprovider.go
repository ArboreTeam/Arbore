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

// LLMLimits décrit ce que le fournisseur accepte en régime nominal.
//
// Seul le débit en requêtes est retenu : chez Mistral, une requête /diagnose
// complète pèse environ 2 000 tokens (image comprise), donc 60 requêtes par
// minute en consomment ~120 000 pour un plafond de 500 000. On sature les
// requêtes bien avant les tokens, et compter ces derniers reviendrait à
// surveiller une limite qu'on n'atteint jamais — avec l'inconvénient qu'ils ne
// sont pas connaissables avant l'appel.
type LLMLimits struct {
	// RequestsPerSecond est le débit soutenable. Zéro signifie « aucune limite
	// connue » : le fournisseur n'est alors pas étranglé du tout.
	RequestsPerSecond float64
}

// LLMProvider abstrait un modèle de chat/vision derrière une interface stable.
type LLMProvider interface {
	// Name identifie le fournisseur (télémétrie, logs).
	Name() string
	// Limits déclare le débit soutenable, pour que l'étranglement se configure
	// sans rien savoir du fournisseur concret.
	Limits() LLMLimits
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
	case "mistral":
		// ⚠️ Avant de basculer une machine ici : le palier gratuit « Experiment »
		// est opté-IN par défaut dans le programme d'amélioration de Mistral.
		// Désactiver « Anonymous improvement data » dans la console
		// d'administration (menu Privacy) AVANT d'y envoyer des photos
		// d'utilisateurs. Cf. #555 et docs/fr/operations/fournisseurs-llm.md.
		activeLLMProvider = newMistralProvider()
	default:
		return fmt.Errorf("AI_PROVIDER inconnu: %q (attendu: gemini, mistral)", os.Getenv("AI_PROVIDER"))
	}
	// L'étranglement est posé ici, une fois, plutôt que dans chaque
	// implémentation : un fournisseur ajouté demain en hérite sans rien écrire.
	activeLLMProvider = throttled(activeLLMProvider)
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
