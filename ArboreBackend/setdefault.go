package main

func (p *Plant) SetDefaults() {
	// Nom de la plante
	if p.Name == "" {
		p.Name = "Plante inconnue"
	}

	// Type général (ne donne pas d'info de care, juste une étiquette)
	if p.Type == "" {
		p.Type = "Type inconnu"
	}

	// Image de fallback
	if len(p.ImageURLs) == 0 {
		p.ImageURLs = []string{
			"https://via.placeholder.com/600x400?text=Plante",
		}
	}

	// Description globale (top-level)
	if p.Description == "" {
		p.Description = "Description non disponible."
	}

	// URL de modèle (facultatif)
	if p.ModelURL == "" {
		p.ModelURL = ""
	}

	// Translations ne doit jamais être nil
	if p.Translations == nil {
		p.Translations = make(map[string]LanguageData)
	}

	// On s'assure que les 4 langues existent,
	// mais on ne met PAS de faux conseils de soin.
	langs := []string{"fr", "en", "es", "de"}

	for _, code := range langs {
		langData, exists := p.Translations[code]
		if !exists {
			langData = LanguageData{}
		}

		// Description par langue
		if langData.Description == "" {
			switch code {
			case "fr":
				langData.Description = "Aucune information détaillée disponible pour cette plante."
			case "en":
				langData.Description = "No detailed information available for this plant."
			case "es":
				langData.Description = "No hay información detallada disponible para esta planta."
			case "de":
				langData.Description = "Keine detaillierten Informationen für diese Pflanze verfügbar."
			default:
				langData.Description = "No information available."
			}
		}

		// Type de plante (on réutilise p.Type, c'est juste un label, pas un conseil)
		if langData.PlantType == "" {
			langData.PlantType = p.Type
		}

		// ⚠️ On NE TOUCHE PAS à sun / water / soilAndPot / health / lifeCycle / care
		// Si l'IA ne les a pas remplis, ils restent vides.
		// Ce sera à l'app de décider quoi afficher :
		// - soit masquer la section,
		// - soit afficher "Informations non disponibles".

		p.Translations[code] = langData
	}
}
