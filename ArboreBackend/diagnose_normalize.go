package main

import (
	"encoding/json"
	"strings"
)

// Normalisation de la réponse de diagnostic Gemini (issue #312) : on ne renvoie
// jamais au client la sortie brute du modèle, mais une structure typée, bornée
// et sûre, respectant le contrat du décodeur iOS
// (GeminiDiagnosticResponse dans PlantHealthScanner.swift).

const (
	maxDiseases          = 10
	maxRecommendations   = 12
	maxDiseaseNameLen    = 120
	maxRecommendationLen = 500
	maxSpeciesLen        = 120
)

// Structs de SORTIE — clés camelCase exactes attendues par le client (décodage
// sans convertFromSnakeCase). `name` est un string non-pointeur : toujours émis
// et jamais null (côté iOS il est non-optionnel). Les tableaux sont initialisés
// pour n'être jamais null.
type diagnoseDiseaseOut struct {
	Name       string  `json:"name"`
	Severity   float64 `json:"severity"`
	Confidence float64 `json:"confidence"`
}

type diagnoseOut struct {
	Species         *string              `json:"species"`
	OverallHealth   float64              `json:"overallHealth"`
	Diseases        []diagnoseDiseaseOut `json:"diseases"`
	Recommendations []string             `json:"recommendations"`
	IsUncertain     bool                 `json:"isUncertain"`
}

// Structs d'ENTRÉE — pointeurs pour distinguer « absent » de « valeur zéro ».
type diagnoseInDisease struct {
	Name       *string  `json:"name"`
	Severity   *float64 `json:"severity"`
	Confidence *float64 `json:"confidence"`
}

type diagnoseIn struct {
	Species         *string             `json:"species"`
	OverallHealth   *float64            `json:"overallHealth"`
	Diseases        []diagnoseInDisease `json:"diseases"`
	Recommendations []string            `json:"recommendations"`
	IsUncertain     *bool               `json:"isUncertain"`
}

// clampUnit borne une valeur dans [0,1].
func clampUnit(f float64) float64 {
	switch {
	case f < 0:
		return 0
	case f > 1:
		return 1
	default:
		return f
	}
}

// normalizeDiagnose décode la réponse brute du modèle et renvoie une structure
// bornée et sûre : valeurs numériques clampées dans [0,1], tableaux bornés et
// jamais null, maladies sans nom écartées, défauts prudents.
func normalizeDiagnose(raw []byte) (diagnoseOut, error) {
	var in diagnoseIn
	if err := json.Unmarshal(raw, &in); err != nil {
		return diagnoseOut{}, err
	}

	out := diagnoseOut{
		Diseases:        []diagnoseDiseaseOut{},
		Recommendations: []string{},
		IsUncertain:     true, // défaut prudent si le modèle l'omet
	}

	// species : assaini, null si vide.
	if in.Species != nil {
		if s := sanitizeLine(*in.Species, maxSpeciesLen); s != "" {
			out.Species = &s
		}
	}

	if in.OverallHealth != nil {
		out.OverallHealth = clampUnit(*in.OverallHealth)
	}

	if in.IsUncertain != nil {
		out.IsUncertain = *in.IsUncertain
	}

	for _, d := range in.Diseases {
		if len(out.Diseases) >= maxDiseases {
			break
		}
		name := ""
		if d.Name != nil {
			name = sanitizeLine(*d.Name, maxDiseaseNameLen)
		}
		if name == "" {
			continue // maladie sans nom : écartée (name non-optionnel côté iOS)
		}
		disease := diagnoseDiseaseOut{Name: name}
		if d.Severity != nil {
			disease.Severity = clampUnit(*d.Severity)
		}
		if d.Confidence != nil {
			disease.Confidence = clampUnit(*d.Confidence)
		}
		out.Diseases = append(out.Diseases, disease)
	}

	for _, r := range in.Recommendations {
		if len(out.Recommendations) >= maxRecommendations {
			break
		}
		if rec := strings.TrimSpace(truncateRunes(r, maxRecommendationLen)); rec != "" {
			out.Recommendations = append(out.Recommendations, rec)
		}
	}

	return out, nil
}
