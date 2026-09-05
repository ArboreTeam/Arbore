package main

import (
	"encoding/json"
	"testing"
)

func TestPlantBotanicalProfileJSONRoundTrip(t *testing.T) {
	minimum := 4.0
	maximum := 8.0
	version := 1
	plant := Plant{
		Name: "Test plant",
		BotanicalProfile: &PlantBotanicalProfile{
			Environments: &PlantStringListFact{
				Value: []string{"outdoor"},
				Evidence: &PlantDataEvidence{
					SourceName:  "Botanical source",
					SourceURL:   "https://example.test/plant",
					ReviewedAt:  "2026-07-23",
					Reliability: "high",
				},
			},
			MinimumTemperatureC: &PlantNumberFact{Value: -10},
			DirectSunHours: &PlantRangeFact{
				Minimum: &minimum,
				Maximum: &maximum,
				Unit:    "hours/day",
			},
			SchemaVersion: &version,
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
	if decoded.BotanicalProfile == nil {
		t.Fatal("botanical profile was lost")
	}
	if got := decoded.BotanicalProfile.Environments.Value[0]; got != "outdoor" {
		t.Fatalf("environment = %q, want outdoor", got)
	}
	if got := *decoded.BotanicalProfile.DirectSunHours.Maximum; got != 8 {
		t.Fatalf("maximum direct sun = %v, want 8", got)
	}
}

func TestGardenCompatibilityContextJSONRoundTrip(t *testing.T) {
	garden := GardenWizardData{
		ConditionalAnswers: &GardenConditionalAnswersData{
			PlantingMode:         "containers",
			MaximumContainerSize: "medium",
			WateringCapacity:     "regular",
			DirectSunDuration:    "fourToSixHours",
		},
		SiteProfile: &GardenSiteProfileData{
			Climate: &GardenClimateData{
				HistoricalMinimumTemperature: &GardenTemperatureData{
					Celsius: -6,
					Metadata: GardenValueMetadataData{
						Source:          "regionalEstimate",
						Confidence:      "high",
						SourceReference: "Climate normals",
						ObservedAt:      "2026-07-23",
					},
				},
			},
		},
	}

	data, err := json.Marshal(garden)
	if err != nil {
		t.Fatalf("marshal garden: %v", err)
	}

	var decoded GardenWizardData
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal garden: %v", err)
	}
	if got := decoded.ConditionalAnswers.MaximumContainerSize; got != "medium" {
		t.Fatalf("maximum container size = %q, want medium", got)
	}
	if got := decoded.SiteProfile.Climate.HistoricalMinimumTemperature.Celsius; got != -6 {
		t.Fatalf("minimum temperature = %v, want -6", got)
	}
}
