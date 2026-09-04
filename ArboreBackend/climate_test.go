package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestClimateProfileRequiresLocation(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.POST("/climate/profile", climateProfile)

	req, err := http.NewRequest("POST", "/climate/profile", bytes.NewBufferString(`{"location":{"source":"manualCity"}}`))
	require.NoError(t, err)
	req.Header.Set("Content-Type", "application/json")

	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnprocessableEntity, w.Code)
}

func TestClimateProfileReturnsRegionalCoastalEstimate(t *testing.T) {
	geoServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/communes", r.URL.Path)
		assert.Equal(t, "Cherbourg", r.URL.Query().Get("nom"))
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[
			{
				"nom":"Cherbourg-en-Cotentin",
				"centre":{"type":"Point","coordinates":[-1.62,49.64]},
				"departement":{"code":"50"}
			}
		]`))
	}))
	defer geoServer.Close()
	t.Setenv("GEOGOUV_API_BASE_URL", geoServer.URL)
	t.Setenv("METEOFRANCE_API_TOKEN", "")
	t.Setenv("METEOFRANCE_API_KEY", "")

	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.POST("/climate/profile", climateProfile)

	req, err := http.NewRequest("POST", "/climate/profile", bytes.NewBufferString(`{
		"location":{"city":"Cherbourg","source":"manualCity"}
	}`))
	require.NoError(t, err)
	req.Header.Set("Content-Type", "application/json")

	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	require.Equal(t, http.StatusOK, w.Code)

	var response climateProfileResponse
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &response))
	require.NotNil(t, response.SiteProfile.Wind)
	require.NotNil(t, response.SiteProfile.Climate)
	require.NotNil(t, response.SiteProfile.Climate.HistoricalMinimumTemperature)
	require.NotNil(t, response.SiteProfile.Climate.CoastalExposure)

	assert.Equal(t, "moderate", response.SiteProfile.Wind.Level)
	assert.Equal(t, -6.0, response.SiteProfile.Climate.HistoricalMinimumTemperature.Celsius)
	assert.Equal(t, "occasional", response.SiteProfile.Climate.FrostRisk.Level)
	assert.True(t, response.SiteProfile.Climate.CoastalExposure.IsCoastal)
	assert.Equal(t, "medium", response.SiteProfile.Climate.HistoricalMinimumTemperature.Metadata.Confidence)
	assert.Contains(t, response.Attribution, "estimation régionale Arbore")
}

func TestBuildClimateProfileAddsNearestStationAltitudeWhenConfigured(t *testing.T) {
	geoServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[
			{
				"nom":"Marseille",
				"centre":{"type":"Point","coordinates":[5.37,43.30]},
				"departement":{"code":"13"}
			}
		]`))
	}))
	defer geoServer.Close()

	climateServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/liste-stations/quotidienne", r.URL.Path)
		assert.Equal(t, "13", r.URL.Query().Get("id-departement"))
		assert.Equal(t, "Bearer test-token", r.Header.Get("Authorization"))
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[
			{"id":"far","nom":"Station loin","lat":45.00,"lon":6.00,"altitude":900},
			{"id":"marignane","nom":"Marseille-Marignane","lat":43.44,"lon":5.21,"altitude":32}
		]`))
	}))
	defer climateServer.Close()

	t.Setenv("GEOGOUV_API_BASE_URL", geoServer.URL)
	t.Setenv("METEOFRANCE_CLIMATE_BASE_URL", climateServer.URL)
	t.Setenv("METEOFRANCE_API_TOKEN", "test-token")

	lat, lon := 43.30, 5.37
	profile, _ := buildClimateProfile(context.Background(), GardenLocationData{
		City:      "Marseille",
		Latitude:  &lat,
		Longitude: &lon,
		Source:    "manualCity",
	})

	require.NotNil(t, profile.Climate)
	require.NotNil(t, profile.Climate.Altitude)
	require.NotNil(t, profile.Climate.HistoricalMinimumTemperature)

	assert.Equal(t, 32.0, profile.Climate.Altitude.Meters)
	assert.Equal(t, -4.0, profile.Climate.HistoricalMinimumTemperature.Celsius)
	assert.Contains(t, profile.Climate.HistoricalMinimumTemperature.Metadata.SourceReference, "Marseille-Marignane")
	assert.True(t, profile.Climate.CoastalExposure.IsCoastal)
}

func TestEstimateRegionalClimateFallsBackWithLowConfidence(t *testing.T) {
	zone := estimateRegionalClimate(resolvedClimateLocation{City: "Ville inconnue"})

	assert.Equal(t, "temperate", zone.Name)
	assert.Equal(t, "low", zone.Confidence)
	assert.Equal(t, -8.0, zone.MinC)
	assert.Equal(t, "regular", zone.Frost)
}
