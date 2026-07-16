package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// config.go — endpoint /config (issue #236)
//
// Sert la configuration du wizard de création de jardin et les règles de soin
// depuis le backend, afin que les clients (iOS + web) puissent récupérer les
// options dynamiquement plutôt que de les coder en dur.
//
// Chaque option porte un champ `tier` ("free" | "premium") pour préparer le
// contrôle des styles payants/gratuits (cf. #4 Paiement). Pendant la bêta,
// `membership.enforced = false` : tout est accessible, le `tier` est purement
// informatif. Le jour où l'on activera le gating, il suffira de passer
// `enforced` à true et le backend rejettera les options premium pour les
// comptes sans abonnement — sans rien changer côté config.

// configVersion est incrémenté à chaque modification du contenu servi.
// Les clients peuvent comparer cette valeur pour invalider leur cache local.
//
// v3 : l'entrée du wizard devient un choix d'espace en quatre cartes
// (pièce, balcon, terrasse, jardin).
const configVersion = 3

// wizardOption représente une option proposée dans le questionnaire de jardin.
type wizardOption struct {
	Value string `json:"value"`          // identifiant stable (raw value Swift)
	Label string `json:"label"`          // libellé affiché (FR)
	Icon  string `json:"icon,omitempty"` // SF Symbol / nom d'icône
	Tier  string `json:"tier"`           // "free" | "premium"
}

const (
	tierFree    = "free"
	tierPremium = "premium"
)

// free construit une option gratuite (cas par défaut pendant la bêta).
func free(value, label, icon string) wizardOption {
	return wizardOption{Value: value, Label: label, Icon: icon, Tier: tierFree}
}

// getConfig répond au GET /config.
//
// Accessible avec uniquement l'API key (pas de session Firebase requise) :
// la config est une donnée de référence non sensible, nécessaire dès le
// lancement de l'app avant même que l'utilisateur soit authentifié.
func getConfig(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"version": configVersion,

		// Pendant la bêta gratuite, aucun gating : tous les tiers sont
		// accessibles. Les clients peuvent afficher un badge "Premium" mais
		// ne doivent rien bloquer tant que enforced == false.
		"membership": gin.H{
			"enforced": false,
			"tiers":    []string{tierFree, tierPremium},
		},

		// Options du questionnaire de création de jardin.
		// `value` = nom du cas Swift (clé stable), `label` = rawValue affiché,
		// `icon` = iconName (SF Symbol). Aligné sur QuestionnaireView.swift.
		"wizard": gin.H{
			// Styles de jardin — premiers candidats au gating premium (#4).
			"gardenStyles": []wizardOption{
				free("modern", "Moderne & minimaliste", "square.grid.2x2"),
				free("floral", "Fleuri & coloré", "camera.macro"),
				free("wild", "Champêtre & sauvage", "leaf"),
				free("zen", "Zen & japonais", "wind"),
				free("mediterranean", "Méditerranéen", "sun.max"),
				free("noPreference", "Sans préférence", "sparkles"),
			},

			// Type d'espace à aménager.
			"spaceTypes": []wizardOption{
				free("interior", "Pièce", "house"),
				free("balcony", "Balcon", "building.2"),
				free("terrace", "Terrasse", "chair.lounge"),
				free("garden", "Jardin", "house.and.flag"),
			},

			// Exposition au soleil.
			"sunExposures": []wizardOption{
				free("fullSun", "Soleil direct (6h+)", "sun.max"),
				free("partialShade", "Mi-ombre", "cloud.sun"),
				free("shade", "Ombragé", "cloud"),
				free("unknown", "Je ne sais pas", "questionmark.circle"),
			},

			// Type de sol (étape affichée seulement pour un jardin extérieur).
			"soilTypes": []wizardOption{
				free("rich", "Riche", "leaf"),
				free("dry", "Sec", "sun.max"),
				free("rocky", "Rocailleux", "mountain.2"),
				free("waterRetentive", "Retient l'eau", "drop"),
				free("unknown", "Je ne sais pas", "questionmark.circle"),
			},

			// Niveau d'entretien souhaité.
			"maintenanceLevels": []wizardOption{
				free("veryEasy", "Très facile", "hand.thumbsup"),
				free("easy", "Facile", "leaf"),
				free("demanding", "Exigeant", "wrench.and.screwdriver"),
			},

			// Contraintes de sécurité (animaux / enfants, multi-sélection).
			"safetyOptions": []wizardOption{
				free("pets", "Éviter les plantes toxiques pour les animaux", "pawprint"),
				free("children", "Éviter les plantes dangereuses pour les enfants", "person.2"),
				free("none", "Aucune contrainte", "checkmark.shield"),
			},
		},

		// Règles de soin : intervalles par défaut (en jours) et fréquences
		// d'arrosage, alignés sur GardenCareKind / WateringFrequency (iOS).
		"care": gin.H{
			// Intervalle par défaut de chaque type d'action d'entretien.
			"intervalsDays": gin.H{
				"pruneLeaves": 30,
				"cleanLeaves": 14,
				"fertilize":   21,
				"repot":       180,
				"pestCheck":   14,
				"rotatePot":   7,
				"soilCheck":   7,
				"custom":      14,
			},
			// Correspondance fréquence d'arrosage -> nombre de jours.
			"wateringFrequencyDays": gin.H{
				"daily":       1,
				"twiceWeekly": 3,
				"weekly":      7,
				"biweekly":    14,
				"monthly":     30,
				"custom":      7,
			},
		},

		// Poids du moteur de suggestion (multi-axes, somme ≈ 1.0).
		// Alignés sur GardenSuggestionEngine.Weights (iOS).
		"suggestionEngine": gin.H{
			"weights": gin.H{
				"style":       0.30,
				"exposure":    0.25,
				"soil":        0.20,
				"maintenance": 0.15,
				"safety":      0.10,
			},
		},
	})
}
