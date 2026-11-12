package main

import (
	"encoding/json"
	"testing"
)

// Le verdict de toxicité est une valeur close, et non une phrase à relire.
//
// Le champ portait auparavant de la prose sourcée, et le client en tirait un
// verdict par sous-chaînes. Il testait la liste sûre avant la liste toxique, et
// `safe` est une sous-chaîne de `unsafe` : toute phrase niant l'innocuité était
// donc rendue « sûre » (#778).

func TestVerdictToxiciteAccepteLeVocabulaireFerme(t *testing.T) {
	for _, v := range []string{"safe", "toxic", "irritant", "unknown"} {
		if !VerdictToxiciteValide(v) {
			t.Errorf("%q devrait appartenir au vocabulaire", v)
		}
	}
}

func TestVerdictToxiciteTolereCasseEtEspaces(t *testing.T) {
	for _, v := range []string{"TOXIC", " safe ", "Irritant", "\tunknown\n"} {
		if !VerdictToxiciteValide(v) {
			t.Errorf("%q devrait être accepté après normalisation", v)
		}
	}
}

// Les valeurs ci-dessous sont celles qui inversaient l'ancien analyseur, plus
// la prose que les fiches portaient réellement. Aucune n'appartient au
// vocabulaire : le client doit les traiter comme `unknown`, jamais `safe`.
func TestVerdictToxiciteRefuseLaProse(t *testing.T) {
	refusees := []string{
		"",
		"unsafe for cats and dogs",
		"not safe around children",
		"toxicity not established — treat as unknown, not as safe",
		"toxic to dogs, cats, horses",
		"non-toxic",
		"Non-toxic to dogs, cats and horses per the ASPCA",
		"toxic risk unresolved - rather than proven harmless",
	}
	for _, v := range refusees {
		if VerdictToxiciteValide(v) {
			t.Errorf("%q ne devrait PAS appartenir au vocabulaire fermé", v)
		}
	}
}

func TestPlantToxicityFactJSONRoundTrip(t *testing.T) {
	plant := Plant{
		Name: "Olivier",
		BotanicalProfile: &PlantBotanicalProfile{
			PetToxicity: &PlantToxicityFact{
				Value: "unknown",
				Detail: "toxic risk unresolved - no veterinary reference classifies " +
					"Olea europaea either way",
				Evidence: &PlantDataEvidence{
					SourceName:  "ASPCA Toxic and Non-Toxic Plants",
					SourceURL:   "https://example.test/plant",
					ReviewedAt:  "2026-11-06",
					Reliability: "unresolved",
				},
			},
			ChildToxicity: &PlantToxicityFact{Value: "toxic"},
		},
	}

	data, err := json.Marshal(plant)
	if err != nil {
		t.Fatalf("marshal plant: %v", err)
	}

	var decoded Plant
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal plant: %v", err)
	}
	profil := decoded.BotanicalProfile
	if profil == nil || profil.PetToxicity == nil {
		t.Fatal("le fait de toxicité a été perdu")
	}
	if got := profil.PetToxicity.Value; got != "unknown" {
		t.Fatalf("verdict animaux = %q, attendu unknown", got)
	}
	if profil.PetToxicity.Detail == "" {
		t.Fatal("la prose explicative doit survivre au round-trip")
	}
	if got := profil.ChildToxicity.Value; got != "toxic" {
		t.Fatalf("verdict enfants = %q, attendu toxic", got)
	}
	// `detail` est optionnel : son absence ne doit pas apparaître dans le JSON.
	brut, err := json.Marshal(profil.ChildToxicity)
	if err != nil {
		t.Fatalf("marshal fait enfants: %v", err)
	}
	if got := string(brut); got != `{"value":"toxic"}` {
		t.Fatalf("fait sans prose ni provenance sérialisé en %s", got)
	}
}
