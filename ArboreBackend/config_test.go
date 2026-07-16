package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

// TestGetConfig vérifie la forme de la réponse de GET /config (#236) :
// version, membership non-enforced pendant la bêta, options du wizard avec
// un tier par défaut "free", et règles de soin.
func TestGetConfig(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET("/config", getConfig)

	req, _ := http.NewRequest(http.MethodGet, "/config", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var body map[string]interface{}
	assert.NoError(t, json.Unmarshal(w.Body.Bytes(), &body))

	// Version présente
	assert.Equal(t, float64(configVersion), body["version"])

	// Membership : pas de gating pendant la bêta
	membership, ok := body["membership"].(map[string]interface{})
	assert.True(t, ok, "membership doit être un objet")
	assert.Equal(t, false, membership["enforced"])

	// Wizard : styles présents, chaque option a un tier
	wizard, ok := body["wizard"].(map[string]interface{})
	assert.True(t, ok, "wizard doit être un objet")
	styles, ok := wizard["gardenStyles"].([]interface{})
	assert.True(t, ok, "gardenStyles doit être une liste")
	assert.Len(t, styles, 6)
	for _, s := range styles {
		opt := s.(map[string]interface{})
		assert.NotEmpty(t, opt["value"])
		assert.NotEmpty(t, opt["label"])
		assert.Equal(t, tierFree, opt["tier"], "tout doit être free pendant la bêta")
	}

	spaceTypes, ok := wizard["spaceTypes"].([]interface{})
	assert.True(t, ok, "spaceTypes doit être une liste")
	assert.Len(t, spaceTypes, 4)
	assert.Equal(t, "interior", spaceTypes[0].(map[string]interface{})["value"])
	assert.Equal(t, "balcony", spaceTypes[1].(map[string]interface{})["value"])
	assert.Equal(t, "terrace", spaceTypes[2].(map[string]interface{})["value"])
	assert.Equal(t, "garden", spaceTypes[3].(map[string]interface{})["value"])

	// Care : intervalles de soin présents
	care, ok := body["care"].(map[string]interface{})
	assert.True(t, ok, "care doit être un objet")
	intervals, ok := care["intervalsDays"].(map[string]interface{})
	assert.True(t, ok)
	assert.Equal(t, float64(180), intervals["repot"])
}
