package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestNormalizeDiagnose_ClampsNumericValues(t *testing.T) {
	raw := `{"overallHealth":1.5,"diseases":[{"name":"Oïdium","severity":-0.2,"confidence":2.0}]}`
	out, err := normalizeDiagnose([]byte(raw))
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if out.OverallHealth != 1.0 {
		t.Fatalf("overallHealth non clampé: %v", out.OverallHealth)
	}
	if len(out.Diseases) != 1 {
		t.Fatalf("attendu 1 maladie, obtenu %d", len(out.Diseases))
	}
	if out.Diseases[0].Severity != 0 || out.Diseases[0].Confidence != 1 {
		t.Fatalf("severity/confidence non clampés: %+v", out.Diseases[0])
	}
}

func TestNormalizeDiagnose_DropsNamelessDiseases(t *testing.T) {
	raw := `{"diseases":[{"name":"Rouille"},{"severity":0.5},{"name":"","confidence":0.3},{"name":"  "}]}`
	out, err := normalizeDiagnose([]byte(raw))
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if len(out.Diseases) != 1 || out.Diseases[0].Name != "Rouille" {
		t.Fatalf("seule la maladie nommée devait rester: %+v", out.Diseases)
	}
}

func TestNormalizeDiagnose_DefaultsAndNeverNullArrays(t *testing.T) {
	out, err := normalizeDiagnose([]byte(`{}`))
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if !out.IsUncertain {
		t.Fatal("isUncertain devrait défaut à true quand absent")
	}
	if out.Species != nil {
		t.Fatalf("species devrait être null quand absent, obtenu %v", *out.Species)
	}
	// Les tableaux ne doivent jamais être null dans le JSON émis.
	b, _ := json.Marshal(out)
	s := string(b)
	if !strings.Contains(s, `"diseases":[]`) || !strings.Contains(s, `"recommendations":[]`) {
		t.Fatalf("tableaux null émis: %s", s)
	}
}

func TestNormalizeDiagnose_EmptySpeciesBecomesNull(t *testing.T) {
	out, err := normalizeDiagnose([]byte(`{"species":"   "}`))
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if out.Species != nil {
		t.Fatalf("species vide devrait devenir null, obtenu %q", *out.Species)
	}
}

func TestNormalizeDiagnose_BoundsCounts(t *testing.T) {
	var sb strings.Builder
	sb.WriteString(`{"diseases":[`)
	for i := 0; i < 25; i++ {
		if i > 0 {
			sb.WriteString(",")
		}
		sb.WriteString(`{"name":"m"}`)
	}
	sb.WriteString(`],"recommendations":[`)
	for i := 0; i < 25; i++ {
		if i > 0 {
			sb.WriteString(",")
		}
		sb.WriteString(`"reco"`)
	}
	sb.WriteString(`]}`)

	out, err := normalizeDiagnose([]byte(sb.String()))
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if len(out.Diseases) != maxDiseases {
		t.Fatalf("diseases non borné: %d", len(out.Diseases))
	}
	if len(out.Recommendations) != maxRecommendations {
		t.Fatalf("recommendations non borné: %d", len(out.Recommendations))
	}
}

func TestNormalizeDiagnose_SanitizesDiseaseName(t *testing.T) {
	raw := `{"diseases":[{"name":"Taches\nnoires"}]}`
	out, err := normalizeDiagnose([]byte(raw))
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if len(out.Diseases) != 1 || strings.Contains(out.Diseases[0].Name, "\n") {
		t.Fatalf("nom de maladie non assaini: %+v", out.Diseases)
	}
	if out.Diseases[0].Name != "Taches noires" {
		t.Fatalf("nom inattendu: %q", out.Diseases[0].Name)
	}
}

func TestNormalizeDiagnose_InvalidJSON(t *testing.T) {
	if _, err := normalizeDiagnose([]byte(`{not json`)); err == nil {
		t.Fatal("attendu une erreur pour du JSON invalide")
	}
}

// La maladie normalisée émet toujours un name non-null (contrainte iOS).
func TestNormalizeDiagnose_DiseaseNameAlwaysEmitted(t *testing.T) {
	out, _ := normalizeDiagnose([]byte(`{"diseases":[{"name":"Mildiou","severity":0.4}]}`))
	b, _ := json.Marshal(out)
	if !strings.Contains(string(b), `"name":"Mildiou"`) {
		t.Fatalf("name non émis correctement: %s", b)
	}
	if strings.Contains(string(b), `"name":null`) {
		t.Fatalf("name null émis: %s", b)
	}
}
