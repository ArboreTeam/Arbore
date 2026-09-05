package main

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

const (
	defaultMeteoFranceClimateBaseURL = "https://public-api.meteofrance.fr/public/DPClim/v1"
	defaultGeoGouvBaseURL            = "https://geo.api.gouv.fr"
	climateRequestTimeout            = 3500 * time.Millisecond
)

type climateProfileRequest struct {
	Location GardenLocationData `json:"location"`
}

type climateProfileResponse struct {
	SiteProfile GardenSiteProfileData `json:"siteProfile"`
	Attribution string                `json:"attribution,omitempty"`
}

type resolvedClimateLocation struct {
	City           string
	DepartmentCode string
	Latitude       *float64
	Longitude      *float64
}

type meteoFranceStation struct {
	ID        string
	Name      string
	Latitude  float64
	Longitude float64
	Altitude  *float64
}

type regionalClimateZone struct {
	Name        string
	MinC        float64
	MaxC        float64
	Frost       string
	Wind        string
	IsCoastal   bool
	Confidence  string
	Description string
}

func climateProfile(c *gin.Context) {
	var payload climateProfileRequest
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if !hasUsableClimateLocation(payload.Location) {
		c.JSON(http.StatusUnprocessableEntity, gin.H{"error": "location is required"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), climateRequestTimeout)
	defer cancel()

	profile, attribution := buildClimateProfile(ctx, payload.Location)
	c.JSON(http.StatusOK, climateProfileResponse{
		SiteProfile: profile,
		Attribution: attribution,
	})
}

func hasUsableClimateLocation(location GardenLocationData) bool {
	return strings.TrimSpace(location.City) != "" || (location.Latitude != nil && location.Longitude != nil)
}

func buildClimateProfile(ctx context.Context, location GardenLocationData) (GardenSiteProfileData, string) {
	resolved := resolveClimateLocation(ctx, location)
	zone := estimateRegionalClimate(resolved)
	now := time.Now().UTC().Format(time.RFC3339)
	sourceReference := "Estimation régionale Arbore"
	attribution := "Source : estimation régionale Arbore à partir de la localisation approximative."
	confidence := zone.Confidence

	var station *meteoFranceStation
	if resolved.DepartmentCode != "" {
		if nearest, err := nearestMeteoFranceStation(ctx, resolved); err == nil {
			station = nearest
			sourceReference = "Météo-France Données Publiques, station " + nearest.Name
			attribution = "Source : Météo-France Données Publiques, réutilisation sous Licence Ouverte Etalab 2.0."
			if nearest.ID != "" {
				sourceReference += " (" + nearest.ID + ")"
			}
			if confidence == "low" {
				confidence = "medium"
			}
		}
	}

	metadata := GardenValueMetadataData{
		Source:          "regionalEstimate",
		Confidence:      confidence,
		SourceReference: sourceReference,
		ObservedAt:      now,
	}

	climate := &GardenClimateData{
		HistoricalMinimumTemperature: &GardenTemperatureData{
			Celsius:  roundClimateValue(zone.MinC),
			Metadata: metadata,
		},
		HistoricalMaximumTemperature: &GardenTemperatureData{
			Celsius:  roundClimateValue(zone.MaxC),
			Metadata: metadata,
		},
		FrostRisk: &GardenFrostRiskData{
			Level:    zone.Frost,
			Metadata: metadata,
		},
		CoastalExposure: &GardenCoastalExposureData{
			IsCoastal: zone.IsCoastal,
			Metadata:  metadata,
		},
	}

	if station != nil && station.Altitude != nil {
		climate.Altitude = &GardenAltitudeData{
			Meters:   roundClimateValue(*station.Altitude),
			Metadata: metadata,
		}
	}

	profile := GardenSiteProfileData{
		Wind: &GardenWindData{
			Level:    zone.Wind,
			Metadata: metadata,
		},
		Climate:       climate,
		PlantingZones: []GardenPlantingZoneData{},
	}

	return profile, attribution
}

func resolveClimateLocation(ctx context.Context, location GardenLocationData) resolvedClimateLocation {
	resolved := resolvedClimateLocation{
		City:      strings.TrimSpace(location.City),
		Latitude:  location.Latitude,
		Longitude: location.Longitude,
	}

	if geo, err := resolveGeoGouvLocation(ctx, location); err == nil {
		if geo.City != "" {
			resolved.City = geo.City
		}
		if geo.DepartmentCode != "" {
			resolved.DepartmentCode = geo.DepartmentCode
		}
		if resolved.Latitude == nil && geo.Latitude != nil {
			resolved.Latitude = geo.Latitude
		}
		if resolved.Longitude == nil && geo.Longitude != nil {
			resolved.Longitude = geo.Longitude
		}
	}

	if resolved.DepartmentCode == "" {
		resolved.DepartmentCode = departmentHintForCity(resolved.City)
	}

	return resolved
}

func resolveGeoGouvLocation(ctx context.Context, location GardenLocationData) (resolvedClimateLocation, error) {
	baseURL := strings.TrimRight(os.Getenv("GEOGOUV_API_BASE_URL"), "/")
	if baseURL == "" {
		baseURL = defaultGeoGouvBaseURL
	}

	values := url.Values{}
	values.Set("fields", "nom,centre,departement")
	values.Set("format", "json")
	values.Set("limit", "1")

	if location.Latitude != nil && location.Longitude != nil {
		values.Set("lat", strconv.FormatFloat(*location.Latitude, 'f', 4, 64))
		values.Set("lon", strconv.FormatFloat(*location.Longitude, 'f', 4, 64))
	} else if strings.TrimSpace(location.City) != "" {
		values.Set("nom", strings.TrimSpace(location.City))
		values.Set("boost", "population")
	} else {
		return resolvedClimateLocation{}, errors.New("missing location")
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL+"/communes?"+values.Encode(), nil)
	if err != nil {
		return resolvedClimateLocation{}, err
	}
	req.Header.Set("Accept", "application/json")

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return resolvedClimateLocation{}, err
	}
	defer res.Body.Close()

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return resolvedClimateLocation{}, errors.New("geo api status " + strconv.Itoa(res.StatusCode))
	}

	var communes []struct {
		Name   string `json:"nom"`
		Center struct {
			Type        string    `json:"type"`
			Coordinates []float64 `json:"coordinates"`
		} `json:"centre"`
		Department struct {
			Code string `json:"code"`
		} `json:"departement"`
	}
	if err := json.NewDecoder(res.Body).Decode(&communes); err != nil {
		return resolvedClimateLocation{}, err
	}
	if len(communes) == 0 {
		return resolvedClimateLocation{}, errors.New("no commune")
	}

	out := resolvedClimateLocation{
		City:           communes[0].Name,
		DepartmentCode: communes[0].Department.Code,
	}
	if len(communes[0].Center.Coordinates) >= 2 {
		lon := communes[0].Center.Coordinates[0]
		lat := communes[0].Center.Coordinates[1]
		out.Latitude = &lat
		out.Longitude = &lon
	}
	return out, nil
}

func nearestMeteoFranceStation(ctx context.Context, location resolvedClimateLocation) (*meteoFranceStation, error) {
	token := strings.TrimSpace(os.Getenv("METEOFRANCE_API_TOKEN"))
	if token == "" {
		token = strings.TrimSpace(os.Getenv("METEOFRANCE_API_KEY"))
	}
	if token == "" || location.DepartmentCode == "" {
		return nil, errors.New("meteo france token or department missing")
	}

	baseURL := strings.TrimRight(os.Getenv("METEOFRANCE_CLIMATE_BASE_URL"), "/")
	if baseURL == "" {
		baseURL = defaultMeteoFranceClimateBaseURL
	}

	values := url.Values{}
	values.Set("id-departement", location.DepartmentCode)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL+"/liste-stations/quotidienne?"+values.Encode(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("apikey", token)

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return nil, errors.New("meteo france status " + strconv.Itoa(res.StatusCode))
	}

	var raw []map[string]interface{}
	if err := json.NewDecoder(res.Body).Decode(&raw); err != nil {
		return nil, err
	}

	stations := make([]meteoFranceStation, 0, len(raw))
	for _, item := range raw {
		if station, ok := parseMeteoFranceStation(item); ok {
			stations = append(stations, station)
		}
	}
	if len(stations) == 0 {
		return nil, errors.New("no station")
	}

	sort.Slice(stations, func(i, j int) bool {
		return stationDistance(stations[i], location) < stationDistance(stations[j], location)
	})
	return &stations[0], nil
}

func parseMeteoFranceStation(item map[string]interface{}) (meteoFranceStation, bool) {
	lat, latOK := mapFloat(item, "lat", "latitude", "Latitude", "LAT")
	lon, lonOK := mapFloat(item, "lon", "lng", "longitude", "Longitude", "LON")
	if !latOK || !lonOK {
		if geo, ok := item["geo_point_2d"].(map[string]interface{}); ok {
			lat, latOK = mapFloat(geo, "lat", "latitude")
			lon, lonOK = mapFloat(geo, "lon", "lng", "longitude")
		}
	}
	if !latOK || !lonOK {
		return meteoFranceStation{}, false
	}

	altitude, _ := mapFloat(item, "altitude", "alt", "Altitude", "ALTI")
	station := meteoFranceStation{
		ID:        mapString(item, "id", "id_station", "idStation", "ID", "num_poste"),
		Name:      mapString(item, "nom", "name", "Nom", "NAME", "libelle"),
		Latitude:  lat,
		Longitude: lon,
	}
	if station.Name == "" {
		station.Name = "station proche"
	}
	if altitude != 0 {
		station.Altitude = &altitude
	}
	return station, true
}

func mapFloat(item map[string]interface{}, keys ...string) (float64, bool) {
	for _, key := range keys {
		switch value := item[key].(type) {
		case float64:
			return value, true
		case int:
			return float64(value), true
		case json.Number:
			parsed, err := value.Float64()
			return parsed, err == nil
		case string:
			parsed, err := strconv.ParseFloat(strings.ReplaceAll(value, ",", "."), 64)
			if err == nil {
				return parsed, true
			}
		}
	}
	return 0, false
}

func mapString(item map[string]interface{}, keys ...string) string {
	for _, key := range keys {
		if value, ok := item[key].(string); ok {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func stationDistance(station meteoFranceStation, location resolvedClimateLocation) float64 {
	if location.Latitude == nil || location.Longitude == nil {
		return 0
	}
	latDelta := station.Latitude - *location.Latitude
	lonDelta := station.Longitude - *location.Longitude
	return latDelta*latDelta + lonDelta*lonDelta
}

func estimateRegionalClimate(location resolvedClimateLocation) regionalClimateZone {
	city := normalizeClimateText(location.City)
	lat, lon := 46.6, 2.4
	if location.Latitude != nil {
		lat = *location.Latitude
	}
	if location.Longitude != nil {
		lon = *location.Longitude
	}

	if isMediterraneanClimate(city, lat, lon) {
		return regionalClimateZone{
			Name:        "mediterranean",
			MinC:        -4,
			MaxC:        35,
			Frost:       "occasional",
			Wind:        "moderate",
			IsCoastal:   isCoastalClimate(city, lat, lon),
			Confidence:  "medium",
			Description: "été chaud et sec",
		}
	}
	if isMountainClimate(city, lat, lon) {
		return regionalClimateZone{
			Name:        "mountain",
			MinC:        -15,
			MaxC:        26,
			Frost:       "severe",
			Wind:        "moderate",
			IsCoastal:   false,
			Confidence:  "medium",
			Description: "relief et hivers froids",
		}
	}
	if isOceanicClimate(city, lat, lon) {
		return regionalClimateZone{
			Name:        "oceanic",
			MinC:        -6,
			MaxC:        29,
			Frost:       "occasional",
			Wind:        coastalWindLevel(city, lat, lon),
			IsCoastal:   isCoastalClimate(city, lat, lon),
			Confidence:  "medium",
			Description: "hiver doux et humidité régulière",
		}
	}
	if isContinentalClimate(city, lat, lon) {
		return regionalClimateZone{
			Name:        "continental",
			MinC:        -12,
			MaxC:        31,
			Frost:       "regular",
			Wind:        "light",
			IsCoastal:   false,
			Confidence:  "medium",
			Description: "écarts saisonniers marqués",
		}
	}

	return regionalClimateZone{
		Name:        "temperate",
		MinC:        -8,
		MaxC:        30,
		Frost:       "regular",
		Wind:        "light",
		IsCoastal:   isCoastalClimate(city, lat, lon),
		Confidence:  "low",
		Description: "estimation tempérée générale",
	}
}

func normalizeClimateText(value string) string {
	replacer := strings.NewReplacer(
		"à", "a", "â", "a", "ä", "a",
		"ç", "c",
		"é", "e", "è", "e", "ê", "e", "ë", "e",
		"î", "i", "ï", "i",
		"ô", "o", "ö", "o",
		"ù", "u", "û", "u", "ü", "u",
	)
	return replacer.Replace(strings.ToLower(strings.TrimSpace(value)))
}

func containsClimateCity(city string, names ...string) bool {
	for _, name := range names {
		if strings.Contains(city, normalizeClimateText(name)) {
			return true
		}
	}
	return false
}

func isMountainClimate(city string, lat, lon float64) bool {
	if containsClimateCity(city, "chamonix", "grenoble", "annecy", "gap", "briançon", "tarbes", "lourdes", "foix") {
		return true
	}
	return (lat >= 43.0 && lat <= 46.6 && lon >= 5.2 && lon <= 7.9) ||
		(lat >= 42.3 && lat <= 43.8 && lon >= -1.0 && lon <= 2.5) ||
		(lat >= 45.0 && lat <= 47.2 && lon >= 5.4 && lon <= 7.4)
}

func isMediterraneanClimate(city string, lat, lon float64) bool {
	if containsClimateCity(city, "marseille", "nice", "toulon", "montpellier", "nimes", "perpignan", "avignon", "cannes", "ajaccio", "bastia") {
		return true
	}
	return lat >= 41.3 && lat <= 44.4 && lon >= 2.0 && lon <= 9.8
}

func isOceanicClimate(city string, lat, lon float64) bool {
	if containsClimateCity(city, "brest", "cherbourg", "saint-malo", "rennes", "nantes", "la rochelle", "bordeaux", "bayonne", "biarritz", "caen", "le havre", "lille") {
		return true
	}
	return (lat >= 43.0 && lat <= 51.3 && lon <= 0.8) || (lat >= 48.5 && lon <= 3.2)
}

func isContinentalClimate(city string, lat, lon float64) bool {
	if containsClimateCity(city, "strasbourg", "mulhouse", "nancy", "metz", "dijon", "besançon", "reims") {
		return true
	}
	return lat >= 46.5 && lon >= 4.0
}

func isCoastalClimate(city string, lat, lon float64) bool {
	if containsClimateCity(city, "brest", "cherbourg", "saint-malo", "la rochelle", "bordeaux", "bayonne", "biarritz", "marseille", "nice", "toulon", "perpignan", "ajaccio", "bastia", "le havre", "dunkerque") {
		return true
	}
	return (lat >= 41.3 && lat <= 44.3 && lon >= 2.8 && lon <= 9.8) ||
		(lat >= 43.0 && lat <= 51.3 && lon <= -1.0)
}

func coastalWindLevel(city string, lat, lon float64) string {
	if isCoastalClimate(city, lat, lon) {
		return "moderate"
	}
	return "light"
}

func departmentHintForCity(city string) string {
	city = normalizeClimateText(city)
	hints := map[string]string{
		"paris":       "75",
		"marseille":   "13",
		"lyon":        "69",
		"toulouse":    "31",
		"nice":        "06",
		"nantes":      "44",
		"montpellier": "34",
		"strasbourg":  "67",
		"bordeaux":    "33",
		"lille":       "59",
		"rennes":      "35",
		"reims":       "51",
		"toulon":      "83",
		"grenoble":    "38",
		"dijon":       "21",
		"angers":      "49",
		"nimes":       "30",
		"brest":       "29",
		"perpignan":   "66",
		"caen":        "14",
		"cherbourg":   "50",
		"bayonne":     "64",
		"biarritz":    "64",
		"ajaccio":     "2A",
		"bastia":      "2B",
	}
	for key, department := range hints {
		if strings.Contains(city, key) {
			return department
		}
	}
	return ""
}

func roundClimateValue(value float64) float64 {
	return math.Round(value*10) / 10
}
