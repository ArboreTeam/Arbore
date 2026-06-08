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
const configVersion = 1

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
		"wizard": gin.H{
			// Styles de jardin — premiers candidats au gating premium (#4).
			"gardenStyles": []wizardOption{
				free("modern", "Moderne", "square.grid.2x2"),
				free("traditional", "Traditionnel", "house"),
				free("japanese", "Japonais", "leaf"),
				free("mediterranean", "Méditerranéen", "sun.max"),
				free("cottage", "Cottage", "house.lodge"),
				free("tropical", "Tropical", "tree"),
				free("minimalist", "Minimaliste", "minus.square"),
				free("wild", "Sauvage/Naturel", "mountain.2"),
			},

			// Type d'espace à aménager.
			"spaceTypes": []wizardOption{
				free("room", "Pièce", "door.left.hand.closed"),
				free("outdoor", "Extérieur", "tree"),
				free("both", "Intérieur/Extérieur", "house.and.flag"),
			},

			// Exposition au soleil.
			"sunExposures": []wizardOption{
				free("fullSun", "Plein soleil (6h+)", "sun.max.fill"),
				free("partialSun", "Mi-ombre (3-6h)", "cloud.sun.fill"),
				free("shade", "Ombre (moins de 3h)", "cloud.fill"),
				free("mixed", "Mixte", "sun.haze.fill"),
			},

			// Type de sol.
			"soilTypes": []wizardOption{
				free("clay", "Argileux", "square.stack.3d.up"),
				free("sandy", "Sableux", "circle.grid.3x3"),
				free("loamy", "Limoneux", "leaf.circle"),
				free("chalky", "Calcaire", "mountain.2"),
				free("peaty", "Tourbeux", "drop.fill"),
				free("unknown", "Je ne sais pas", "questionmark.circle"),
			},

			// Niveau d'entretien souhaité.
			"maintenanceLevels": []wizardOption{
				free("veryLow", "Très facile (arrosage rare)", "tortoise"),
				free("low", "Facile (1x/semaine)", "leaf"),
				free("moderate", "Modéré (2-3x/semaine)", "drop"),
				free("high", "Intensif (quotidien)", "hare"),
			},

			// Contraintes de sécurité (animaux / enfants).
			"safetyOptions": []wizardOption{
				free("pets", "Éviter les plantes toxiques pour les animaux", "pawprint"),
				free("children", "Éviter les plantes dangereuses pour les enfants", "person.2"),
				free("none", "Aucune contrainte", "checkmark.shield"),
			},

			// Densité de plantation.
			"densityLevels": []wizardOption{
				free("sparse", "Épuré (peu de plantes)", "circle"),
				free("moderate", "Modéré", "circle.grid.2x2"),
				free("dense", "Dense (beaucoup de plantes)", "circle.grid.3x3.fill"),
			},

			// Niveau d'expérience / complexité des plantes.
			"complexityLevels": []wizardOption{
				free("beginner", "Débutant (plantes résistantes)", "1.circle"),
				free("intermediate", "Intermédiaire", "2.circle"),
				free("advanced", "Expert (plantes exigeantes)", "3.circle"),
				free("mixed", "Mixte", "shuffle"),
			},

			// Budget indicatif.
			"budgetRanges": []wizardOption{
				free("low", "Petit budget (< 100€)", "eurosign.circle"),
				free("medium", "Moyen (100-500€)", "eurosign.circle.fill"),
				free("high", "Élevé (500-1000€)", "creditcard"),
				free("unlimited", "Illimité", "infinity"),
			},

			// Types de plantes recherchés.
			"plantTypes": []wizardOption{
				free("flowers", "Fleurs", "camera.macro"),
				free("shrubs", "Arbustes", "leaf"),
				free("trees", "Arbres", "tree"),
				free("vegetables", "Légumes", "carrot"),
				free("herbs", "Herbes aromatiques", "leaf.circle"),
				free("succulents", "Succulentes", "drop.triangle"),
				free("grasses", "Graminées", "scribble.variable"),
				free("climbers", "Plantes grimpantes", "arrow.up.right"),
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
