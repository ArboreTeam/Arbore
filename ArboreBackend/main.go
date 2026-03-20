// main.go
package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"ArboreBackend/middleware"
)

var client *mongo.Client

type User struct {
	UID              string `json:"uid" bson:"uid"`
	Email            string `json:"email" bson:"email"`
	Name             string `json:"name" bson:"name"`
	CreatedAt        string `json:"createdAt" bson:"createdAt"`
	PhotoData        string `json:"photoData,omitempty" bson:"photoData,omitempty"`
	PhotoContentType string `json:"photoContentType,omitempty" bson:"photoContentType,omitempty"`
	Banned           bool   `json:"banned" bson:"banned"` // Ban status for user moderation
}

// ---------- CONSENT STRUCTS (RGPD) ----------

type ConsentRecord struct {
	ID          primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	UID         string             `json:"uid" bson:"uid"`
	ConsentType string             `json:"consentType" bson:"consentType"`
	Version     string             `json:"version" bson:"version"`
	Granted     bool               `json:"granted" bson:"granted"`
	Timestamp   time.Time          `json:"timestamp" bson:"timestamp"`
	IPAddress   string             `json:"ipAddress,omitempty" bson:"ipAddress,omitempty"`
	UserAgent   string             `json:"userAgent,omitempty" bson:"userAgent,omitempty"`
}

// ---------- PLANTS & AI STRUCTS ----------

type SunInfo struct {
	LightType        string   `json:"lightType" bson:"lightType"`
	DurationPerDay   string   `json:"durationPerDay" bson:"durationPerDay"`
	Orientation      string   `json:"orientation" bson:"orientation"`
	WindowDistance   string   `json:"windowDistance" bson:"windowDistance"`
	RecommendedRooms []string `json:"recommendedRooms" bson:"recommendedRooms"`
	Tips             []string `json:"tips" bson:"tips"`
}

type WaterInfo struct {
	Frequency        string `json:"frequency" bson:"frequency"`
	Amount           string `json:"amount" bson:"amount"`
	Method           string `json:"method" bson:"method"`
	Humidity         string `json:"humidity" bson:"humidity"`
	SignsLack        string `json:"signsLack" bson:"signsLack"`
	SignsExcess      string `json:"signsExcess" bson:"signsExcess"`
	RecommendedWater string `json:"recommendedWater" bson:"recommendedWater"`
}

type SoilAndPotInfo struct {
	Substrate      string `json:"substrate" bson:"substrate"`
	Drainage       string `json:"drainage" bson:"drainage"`
	PotSize        string `json:"potSize" bson:"potSize"`
	RepotFrequency string `json:"repotFrequency" bson:"repotFrequency"`
	RepotSigns     string `json:"repotSigns" bson:"repotSigns"`
}

type HealthInfo struct {
	CommonProblems    []string `json:"commonProblems" bson:"commonProblems"`
	SymptomsAndCauses []string `json:"symptomsAndCauses" bson:"symptomsAndCauses"`
	Pests             []string `json:"pests" bson:"pests"`
	Treatments        []string `json:"treatments" bson:"treatments"`
	Prevention        []string `json:"prevention" bson:"prevention"`
}

type LifeCycleInfo struct {
	Growth     string `json:"growth" bson:"growth"`
	Flowering  string `json:"flowering" bson:"flowering"`
	Dormancy   string `json:"dormancy" bson:"dormancy"`
	Fertilizer string `json:"fertilizer" bson:"fertilizer"`
	Pruning    string `json:"pruning" bson:"pruning"`
}

type CareInfo struct {
	Weekly    []string `json:"weekly" bson:"weekly"`
	Monthly   []string `json:"monthly" bson:"monthly"`
	Yearly    []string `json:"yearly" bson:"yearly"`
	ExtraTips []string `json:"extraTips" bson:"extraTips"`
}

type LanguageData struct {
	Description string         `json:"description" bson:"description"`
	PlantType   string         `json:"plantType" bson:"plantType"`
	Sun         SunInfo        `json:"sun" bson:"sun"`
	Water       WaterInfo      `json:"water" bson:"water"`
	SoilAndPot  SoilAndPotInfo `json:"soilAndPot" bson:"soilAndPot"`
	Health      HealthInfo     `json:"health" bson:"health"`
	LifeCycle   LifeCycleInfo  `json:"lifeCycle" bson:"lifeCycle"`
	Care        CareInfo       `json:"care" bson:"care"`
}

type Plant struct {
	ID           primitive.ObjectID      `bson:"_id,omitempty" json:"id"`
	Name         string                  `json:"name" bson:"name"`
	Type         string                  `json:"type" bson:"type"`
	ImageURLs    []string                `json:"imageURLs" bson:"imageURLs"`
	Description  string                  `json:"description" bson:"description"`
	ModelURL     string                  `json:"modelURL" bson:"modelURL"`
	Translations map[string]LanguageData `json:"translations" bson:"translations"`
}

type AIRequest struct {
	Name string `json:"name"`
}

type AIResponse struct {
	FR LanguageData `json:"fr"`
	EN LanguageData `json:"en"`
	ES LanguageData `json:"es"`
	DE LanguageData `json:"de"`
}

// ---------- GARDENS (NEW) ----------

type GardenWizardData struct {
	Style       string   `json:"style" bson:"style"`
	SpaceType   string   `json:"spaceType" bson:"spaceType"`
	Exposure    string   `json:"exposure,omitempty" bson:"exposure,omitempty"`
	Maintenance string   `json:"maintenance,omitempty" bson:"maintenance,omitempty"`
	Safety      []string `json:"safety,omitempty" bson:"safety,omitempty"`
	Soil        string   `json:"soil,omitempty" bson:"soil,omitempty"`
	ScanMethod  string   `json:"scanMethod,omitempty" bson:"scanMethod,omitempty"`
}

type PlacedPlant struct {
	PlantID primitive.ObjectID `json:"plantId" bson:"plantId"`

	// Optionnel (si tu veux déjà stocker une position simple)
	X float64 `json:"x,omitempty" bson:"x,omitempty"`
	Y float64 `json:"y,omitempty" bson:"y,omitempty"`
	Z float64 `json:"z,omitempty" bson:"z,omitempty"`

	Note string `json:"note,omitempty" bson:"note,omitempty"`
}

type Garden struct {
	ID primitive.ObjectID `json:"id" bson:"_id,omitempty"`

	UID  string `json:"uid" bson:"uid"`
	Name string `json:"name" bson:"name"`

	Wizard GardenWizardData `json:"wizard" bson:"wizard"`
	Plants []PlacedPlant    `json:"plants" bson:"plants"`

	// Pour ta Home: image selon type/style (ex: "modern", "zen", ...)
	ThumbnailKey string `json:"thumbnailKey,omitempty" bson:"thumbnailKey,omitempty"`

	CreatedAt time.Time `json:"createdAt" bson:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt" bson:"updatedAt"`
}

// ---------- HELPER FUNCTIONS ----------

// checkUserBannedFromDB vérifie si l'utilisateur est banni dans MongoDB
func checkUserBannedFromDB(uid string) (bool, error) {
	collection := client.Database("arbore").Collection("users")

	var user User
	err := collection.FindOne(context.Background(), bson.M{"uid": uid}).Decode(&user)

	if err != nil {
		if err == mongo.ErrNoDocuments {
			// Utilisateur n'existe pas → pas banni
			return false, nil
		}
		return false, err
	}

	return user.Banned, nil
}

// ---------- USERS ----------

// exportUserData retourne toutes les données d'un utilisateur (RGPD Article 20 - Portabilité)
func exportUserData(c *gin.Context) {
	authenticatedUID, exists := c.Get("uid")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	uid := authenticatedUID.(string)
	ctx := context.Background()

	// 1. Récupérer les données utilisateur
	var user User
	userCollection := client.Database("arbore").Collection("users")
	err := userCollection.FindOne(ctx, bson.M{"uid": uid}).Decode(&user)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			c.JSON(http.StatusNotFound, gin.H{"error": "Utilisateur non trouvé"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la récupération de l'utilisateur"})
		return
	}

	// 2. Récupérer tous les gardens
	var gardens []Garden
	gardensCollection := client.Database("arbore").Collection("gardens")
	gardensCursor, err := gardensCollection.Find(ctx, bson.M{"uid": uid})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la récupération des gardens"})
		return
	}
	defer func() {
		if err := gardensCursor.Close(ctx); err != nil {
			log.Println("Error closing gardens cursor:", err)
		}
	}()

	if err = gardensCursor.All(ctx, &gardens); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors du décodage des gardens"})
		return
	}

	// 3. Récupérer tous les consentements
	var consents []ConsentRecord
	consentsCollection := client.Database("arbore").Collection("consents")
	consentsCursor, err := consentsCollection.Find(ctx, bson.M{"uid": uid})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la récupération des consentements"})
		return
	}
	defer func() {
		if err := consentsCursor.Close(ctx); err != nil {
			log.Println("Error closing consents cursor:", err)
		}
	}()

	if err = consentsCursor.All(ctx, &consents); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors du décodage des consentements"})
		return
	}

	// 4. Construire la réponse avec toutes les données
	exportData := gin.H{
		"exportDate": time.Now().Format(time.RFC3339),
		"user": gin.H{
			"uid":       user.UID,
			"email":     user.Email,
			"name":      user.Name,
			"createdAt": user.CreatedAt,
			"banned":    user.Banned,
		},
		"gardens":  gardens,
		"consents": consents,
		"metadata": gin.H{
			"totalGardens":  len(gardens),
			"totalConsents": len(consents),
			"format":        "JSON",
			"version":       "1.0",
		},
	}

	c.JSON(http.StatusOK, exportData)
}

func createUser(c *gin.Context) {
	var user User
	if err := c.ShouldBindJSON(&user); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tokenUID, exists := c.Get("uid")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	user.UID = tokenUID.(string)

	fmt.Printf("✅ Donnée reçue dans createUser : %+v\n", user)

	collection := client.Database("arbore").Collection("users")
	_, err := collection.InsertOne(context.Background(), user)
	if err != nil {
		log.Println("❌ Erreur lors de l'insertion dans MongoDB :", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de l'insertion dans MongoDB"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Utilisateur enregistré avec succès", "user": user})
}

func deleteUser(c *gin.Context) {
	authenticatedUID, exists := c.Get("uid")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	uid := authenticatedUID.(string)
	ctx := context.Background()
	db := client.Database("arbore")

	// 1. Supprimer tous les gardens de l'utilisateur
	gardensCollection := db.Collection("gardens")
	gardensResult, err := gardensCollection.DeleteMany(ctx, bson.M{"uid": uid})
	if err != nil {
		log.Println("❌ Erreur lors de la suppression des gardens:", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la suppression des gardens"})
		return
	}
	log.Printf("✅ %d garden(s) supprimé(s)", gardensResult.DeletedCount)

	// 2. Supprimer tous les consentements de l'utilisateur
	consentsCollection := db.Collection("consents")
	consentsResult, err := consentsCollection.DeleteMany(ctx, bson.M{"uid": uid})
	if err != nil {
		log.Println("❌ Erreur lors de la suppression des consents:", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la suppression des consentements"})
		return
	}
	log.Printf("✅ %d consentement(s) supprimé(s)", consentsResult.DeletedCount)

	// 3. Supprimer l'utilisateur
	usersCollection := db.Collection("users")
	userResult, err := usersCollection.DeleteOne(ctx, bson.M{"uid": uid})
	if err != nil {
		log.Println("❌ Erreur lors de la suppression de l'utilisateur:", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la suppression de l'utilisateur"})
		return
	}

	if userResult.DeletedCount == 0 {
		c.JSON(http.StatusNotFound, gin.H{"message": "Aucun utilisateur trouvé avec ce UID"})
		return
	}

	// 4. Logger la suppression complète (audit trail pour RGPD)
	log.Printf("✅ Utilisateur %s supprimé complètement - Gardens: %d, Consents: %d, User: 1",
		uid, gardensResult.DeletedCount, consentsResult.DeletedCount)

	c.JSON(http.StatusOK, gin.H{
		"message":         "Utilisateur supprimé avec succès",
		"gardensDeleted":  gardensResult.DeletedCount,
		"consentsDeleted": consentsResult.DeletedCount,
	})
}

// ---------- CONSENTS (RGPD) ----------

func recordConsent(c *gin.Context) {
	authenticatedUID, exists := c.Get("uid")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var consent ConsentRecord
	if err := c.ShouldBindJSON(&consent); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if consent.ConsentType == "" || consent.Version == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "consentType et version sont requis"})
		return
	}

	consent.UID = authenticatedUID.(string)
	consent.ID = primitive.NewObjectID()

	if consent.Timestamp.IsZero() {
		consent.Timestamp = time.Now()
	}

	if consent.IPAddress == "" {
		consent.IPAddress = c.ClientIP()
	}
	if consent.UserAgent == "" {
		consent.UserAgent = c.GetHeader("User-Agent")
	}

	collection := client.Database("arbore").Collection("consents")
	_, err := collection.InsertOne(context.Background(), consent)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de l'enregistrement du consentement"})
		return
	}

	c.JSON(http.StatusCreated, consent)
}

func getUserConsents(c *gin.Context) {
	authenticatedUID, exists := c.Get("uid")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	uid := authenticatedUID.(string)

	collection := client.Database("arbore").Collection("consents")

	findOptions := options.Find().SetSort(bson.D{{Key: "timestamp", Value: -1}})

	cursor, err := collection.Find(
		context.Background(),
		bson.M{"uid": uid},
		findOptions,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la récupération des consentements"})
		return
	}
	defer func() {
		if err := cursor.Close(context.Background()); err != nil {
			log.Println("Error closing cursor:", err)
		}
	}()

	var consents []ConsentRecord
	if err = cursor.All(context.Background(), &consents); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors du décodage des consentements"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"uid":      uid,
		"count":    len(consents),
		"consents": consents,
	})
}

func getLatestUserConsents(c *gin.Context) {
	authenticatedUID, exists := c.Get("uid")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	uid := authenticatedUID.(string)

	collection := client.Database("arbore").Collection("consents")

	findOptions := options.Find().SetSort(bson.D{{Key: "timestamp", Value: -1}})
	cursor, err := collection.Find(
		context.Background(),
		bson.M{"uid": uid},
		findOptions,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la récupération"})
		return
	}
	defer func() {
		if err := cursor.Close(context.Background()); err != nil {
			log.Println("Error closing cursor:", err)
		}
	}()

	var allConsents []ConsentRecord
	if err = cursor.All(context.Background(), &allConsents); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur de décodage"})
		return
	}

	latestByType := make(map[string]ConsentRecord)
	for _, consent := range allConsents {
		if _, exists := latestByType[consent.ConsentType]; !exists {
			latestByType[consent.ConsentType] = consent
		}
	}

	var latestConsents []ConsentRecord
	for _, consent := range latestByType {
		latestConsents = append(latestConsents, consent)
	}

	c.JSON(http.StatusOK, gin.H{
		"uid":      uid,
		"consents": latestConsents,
	})
}

// ---------- PLANTS CRUD ----------

func createPlant(c *gin.Context) {
	var plant Plant

	if err := c.ShouldBindJSON(&plant); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	collection := client.Database("arbore").Collection("plants")
	plant.ID = primitive.NewObjectID()

	_, err := collection.InsertOne(context.Background(), plant)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de l'insertion de la plante"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "🌱 Plante ajoutée avec succès", "plant": plant})
}

func getPlants(c *gin.Context) {
	collection := client.Database("arbore").Collection("plants")

	cursor, err := collection.Find(context.Background(), bson.M{})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la récupération des plantes"}) // nolint:misspell
		return
	}
	defer func() {
		if err := cursor.Close(context.Background()); err != nil {
			log.Println("Error closing cursor:", err)
		}
	}()

	var plants []Plant
	if err := cursor.All(context.Background(), &plants); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors du décodage des plantes"}) // nolint:misspell
		return
	}

	c.JSON(http.StatusOK, plants)
}

func getPlantByID(c *gin.Context) {
	idParam := c.Param("id")

	objectID, err := primitive.ObjectIDFromHex(idParam)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ID invalide"})
		return
	}

	collection := client.Database("arbore").Collection("plants")

	var plant Plant
	err = collection.FindOne(context.TODO(), bson.M{"_id": objectID}).Decode(&plant)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			c.JSON(http.StatusNotFound, gin.H{"message": "Plante non trouvée"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la récupération de la plante"})
		return
	}

	c.JSON(http.StatusOK, plant)
}

// ---------- AI GENERATION (logique commune) ----------

// Génère une plante avec l'IA + Unsplash + insertion Mongo
// - name: nom de la plante
// Retourne: (plant, alreadyExists, error)
func generateAndInsertPlant(ctx context.Context, name string) (Plant, bool, error) {
	collection := client.Database("arbore").Collection("plants")

	// Vérifie si la plante existe déjà (insensible à la casse)
	filter := bson.M{
		"name": bson.M{"$regex": primitive.Regex{Pattern: "^" + name + "$", Options: "i"}},
	}

	var existing Plant
	err := collection.FindOne(ctx, filter).Decode(&existing)
	if err == nil {
		// Elle existe déjà
		return Plant{}, true, nil
	} else if err != mongo.ErrNoDocuments {
		// Erreur Mongo
		return Plant{}, false, err
	}

	// Appel du microservice IA
	jsonData, _ := json.Marshal(AIRequest{Name: name})
	resp, err := http.Post("http://localhost:8001/generate", "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		log.Println("❌ Erreur appel API IA:", err)
		return Plant{}, false, err
	}
	defer func() {
		if err := resp.Body.Close(); err != nil {
			log.Println("Error closing response body:", err)
		}
	}()

	bodyBytes, _ := io.ReadAll(resp.Body)
	log.Println("🔍 Réponse brute de l'IA (status", resp.StatusCode, "):", string(bodyBytes))

	var aiResponse AIResponse
	err = json.Unmarshal(bodyBytes, &aiResponse)
	if err != nil {
		log.Println("❌ Erreur parsing IA:", err, string(bodyBytes))
		return Plant{}, false, err
	}

	// Images Unsplash
	imageURLs := fetchUnsplashImageURLs(name, 3)

	plant := Plant{
		ID:          primitive.NewObjectID(),
		Name:        name,
		Type:        aiResponse.FR.PlantType,
		ImageURLs:   imageURLs,
		Description: aiResponse.FR.Description,
		ModelURL:    "",
		Translations: map[string]LanguageData{
			"fr": aiResponse.FR,
			"en": aiResponse.EN,
			"es": aiResponse.ES,
			"de": aiResponse.DE,
		},
	}

	_, err = collection.InsertOne(ctx, plant)
	if err != nil {
		log.Println("❌ Erreur lors de l'insertion MongoDB :", err)
		return Plant{}, false, err
	}

	return plant, false, nil
}

// ---------- AI GENERATION : single ----------

func generatePlantWithAI(c *gin.Context) {
	var req AIRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	plant, exists, err := generateAndInsertPlant(context.Background(), req.Name)
	if err != nil {
		log.Println("❌ Erreur lors de la génération de la plante :", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la génération de la plante"})
		return
	}

	if exists {
		c.JSON(http.StatusConflict, gin.H{"error": "🌿 Cette plante existe déjà."})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Plante générée et enregistrée avec succès 🌿",
		"plant":   plant,
	})
}

// ---------- AI GENERATION : multiple ----------

func generateMultiplePlantsHandler(c *gin.Context) {
	var req struct {
		Names []string `json:"names"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Requête invalide"})
		return
	}

	var created []Plant
	var skipped []string

	for _, rawName := range req.Names {
		name := strings.TrimSpace(rawName)
		if name == "" {
			continue
		}

		plant, exists, err := generateAndInsertPlant(context.Background(), name)
		if err != nil {
			log.Println("❌ Erreur lors de la génération pour", name, ":", err)
			skipped = append(skipped, name)
			continue
		}

		if exists {
			// Déjà présente en base → on la met dans skipped
			skipped = append(skipped, name)
			continue
		}

		created = append(created, plant)
	}

	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("%d plante(s) générée(s)", len(created)),
		"created": created,
		"skipped": skipped,
	})
}

// ---------- USER PHOTOS ----------

func uploadUserPhoto(c *gin.Context) {
	uidParam := c.Param("uid")

	tokenUID, exists := c.Get("uid")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	if tokenUID != uidParam {
		c.JSON(http.StatusForbidden, gin.H{"error": "Forbidden: vous ne pouvez modifier que votre propre photo"})
		return
	}

	file, header, err := c.Request.FormFile("photo")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "photo not provided or invalid"})
		return
	}
	defer func() {
		if err := file.Close(); err != nil {
			log.Println("Error closing file:", err)
		}
	}()

	imageBytes, err := io.ReadAll(file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "cannot read uploaded file"})
		return
	}

	encoded := base64.StdEncoding.EncodeToString(imageBytes)
	contentType := header.Header.Get("Content-Type")
	if contentType == "" {
		contentType = http.DetectContentType(imageBytes)
	}

	collection := client.Database("arbore").Collection("users")
	filter := bson.M{"uid": uidParam}
	update := bson.M{"$set": bson.M{
		"photoData":        encoded,
		"photoContentType": contentType,
	}}

	_, err = collection.UpdateOne(context.Background(), filter, update)
	if err != nil {
		log.Println("❌ Erreur lors de la mise à jour photo :", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la sauvegarde de la photo"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Photo enregistrée avec succès"})
}

func getUserPhoto(c *gin.Context) {
	uidParam := c.Param("uid")
	tokenUID, exists := c.Get("uid")
	if !exists || tokenUID.(string) != uidParam {
		c.JSON(http.StatusForbidden, gin.H{"error": "Forbidden"})
		return
	}
	uid := uidParam
	collection := client.Database("arbore").Collection("users")

	var user User
	err := collection.FindOne(context.Background(), bson.M{"uid": uid}).Decode(&user)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			c.Status(http.StatusNotFound)
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la lecture utilisateur"})
		return
	}

	if user.PhotoData == "" {
		c.Status(http.StatusNoContent)
		return
	}

	data, err := base64.StdEncoding.DecodeString(user.PhotoData)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur decoding photo"})
		return
	}

	contentType := user.PhotoContentType
	if contentType == "" {
		contentType = http.DetectContentType(data)
	}

	c.Data(http.StatusOK, contentType, data)
}

// ---------- GARDENS HANDLERS (NEW) ----------

func createGarden(c *gin.Context) {
	var garden Garden
	if err := c.ShouldBindJSON(&garden); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tokenUID, exists := c.Get("uid")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	garden.UID = tokenUID.(string)

	garden.ID = primitive.NewObjectID()
	now := time.Now()
	garden.CreatedAt = now
	garden.UpdatedAt = now

	collection := client.Database("arbore").Collection("gardens")
	_, err := collection.InsertOne(context.Background(), garden)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur insertion garden"})
		return
	}

	c.JSON(http.StatusOK, garden)
}

func listGardens(c *gin.Context) {
	uid, exists := c.Get("uid")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	collection := client.Database("arbore").Collection("gardens")
	opts := options.Find().SetSort(bson.M{"updatedAt": -1})

	cursor, err := collection.Find(context.Background(), bson.M{"uid": uid}, opts)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur find gardens"})
		return
	}
	defer func() {
		if err := cursor.Close(context.Background()); err != nil {
			log.Println("Error closing cursor:", err)
		}
	}()

	var gardens []Garden
	if err := cursor.All(context.Background(), &gardens); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur decode gardens"})
		return
	}

	c.JSON(http.StatusOK, gardens)
}

func getGardenByID(c *gin.Context) {
	idParam := c.Param("id")

	objectID, err := primitive.ObjectIDFromHex(idParam)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ID invalide"})
		return
	}

	collection := client.Database("arbore").Collection("gardens")
	var garden Garden

	err = collection.FindOne(context.Background(), bson.M{"_id": objectID}).Decode(&garden)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			c.JSON(http.StatusNotFound, gin.H{"message": "Garden non trouvé"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lecture garden"})
		return
	}

	c.JSON(http.StatusOK, garden)
}

func updateGarden(c *gin.Context) {
	idParam := c.Param("id")
	objectID, err := primitive.ObjectIDFromHex(idParam)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ID invalide"})
		return
	}

	uid, exists := c.Get("uid")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	// PATCH style (champs optionnels)
	var payload struct {
		Name         *string           `json:"name"`
		Wizard       *GardenWizardData `json:"wizard"`
		Plants       *[]PlacedPlant    `json:"plants"`
		ThumbnailKey *string           `json:"thumbnailKey"`
	}
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	set := bson.M{"updatedAt": time.Now()}
	if payload.Name != nil {
		set["name"] = *payload.Name
	}
	if payload.Wizard != nil {
		set["wizard"] = *payload.Wizard
	}
	if payload.Plants != nil {
		set["plants"] = *payload.Plants
	}
	if payload.ThumbnailKey != nil {
		set["thumbnailKey"] = *payload.ThumbnailKey
	}

	collection := client.Database("arbore").Collection("gardens")
	res, err := collection.UpdateOne(context.Background(), bson.M{"_id": objectID, "uid": uid}, bson.M{"$set": set})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur update garden"})
		return
	}
	if res.MatchedCount == 0 {
		c.JSON(http.StatusNotFound, gin.H{"message": "Garden non trouvé ou accès refusé"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Garden mis à jour"})
}

func deleteGarden(c *gin.Context) {
	idParam := c.Param("id")
	objectID, err := primitive.ObjectIDFromHex(idParam)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ID invalide"})
		return
	}

	uid, exists := c.Get("uid")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	collection := client.Database("arbore").Collection("gardens")
	res, err := collection.DeleteOne(context.Background(), bson.M{"_id": objectID, "uid": uid})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur delete garden"})
		return
	}
	if res.DeletedCount == 0 {
		c.JSON(http.StatusNotFound, gin.H{"message": "Garden non trouvé ou accès refusé"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Garden supprimé"})
}

// ---------- MAIN ----------

func main() {
	// ✅ Recommandé: passe l'URI via env
	// export MONGODB_URI="mongodb+srv://..."
	uri := os.Getenv("MONGODB_URI")

	// ⚠️ Fallback (si tu veux garder ton test local):
	if uri == "" {
		// nolint:gosec // This is a fallback for local development only
		uri = "mongodb+srv://hugorath1234:hugopapa@arbore.cew6l.mongodb.net/arbore?retryWrites=true&w=majority&appName=Arbore"
	}

	clientOptions := options.Client().ApplyURI(uri)

	var err error
	client, err = mongo.Connect(context.Background(), clientOptions)
	if err != nil {
		log.Fatal("❌ Erreur lors de la connexion à MongoDB :", err)
	}

	err = client.Ping(context.Background(), nil)
	if err != nil {
		log.Fatal("❌ Erreur lors de la vérification de la connexion à MongoDB :", err)
	}
	fmt.Println("✅ Connecté à MongoDB!")

	// Initialiser Firebase Admin SDK
	if err := middleware.InitFirebase(); err != nil {
		log.Fatal("❌ Erreur initialisation Firebase:", err)
	}

	// Configurer la fonction de vérification ban pour le middleware
	middleware.CheckUserBannedFunc = checkUserBannedFromDB

	router := gin.Default()

	// === ROUTE PUBLIQUE (Health Check) ===
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status":  "ok",
			"service": "arbore-backend",
			"version": "1.0.0",
		})
	})

	router.GET("/models/thumbnails/:filename", func(c *gin.Context) {
		filename := c.Param("filename")

		if strings.Contains(filename, "..") || strings.Contains(filename, "/") {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid filename"})
			return
		}

		if !strings.HasSuffix(strings.ToLower(filename), ".png") {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Only .png files are allowed"})
			return
		}

		filePath := fmt.Sprintf("/home/fedora/Arbore/ArboreBackend/models/thumbnails/%s", filename)

		fmt.Println("📂 Looking for:", filePath)

		info, err := os.Stat(filePath)
		if err != nil {
			fmt.Println("❌ stat error:", err)
			c.JSON(http.StatusNotFound, gin.H{"error": "Thumbnail not found"})
			return
		}

		fmt.Println("✅ found file, size:", info.Size())

		c.Header("Content-Type", "image/png")
		c.File(filePath)
	})

	// === ROUTES PROTÉGÉES (API Key + Firebase Auth) ===
	// Ordre important: API Key PUIS Firebase Auth
	protected := router.Group("/")
	protected.Use(middleware.APIKeyMiddleware())
	protected.Use(middleware.FirebaseAuthMiddleware())
	{
		// Users
		protected.POST("/users", createUser)
		protected.GET("/users/:uid", func(c *gin.Context) {
			uidParam := c.Param("uid")
			tokenUID, exists := c.Get("uid")
			if !exists || tokenUID.(string) != uidParam {
				c.JSON(http.StatusForbidden, gin.H{"error": "Forbidden"})
				return
			}

			var user User
			collection := client.Database("arbore").Collection("users")
			err := collection.FindOne(context.Background(), bson.M{"uid": uidParam}).Decode(&user)
			if err != nil {
				if err == mongo.ErrNoDocuments {
					c.JSON(http.StatusNotFound, gin.H{"message": "Utilisateur non trouvé"})
					return
				}
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}

			c.JSON(http.StatusOK, gin.H{"user": user})
		})

		protected.POST("/users/:uid/photo", uploadUserPhoto)
		protected.GET("/users/:uid/photo", getUserPhoto)
		protected.GET("/users/export", exportUserData)
		protected.DELETE("/users", deleteUser)

		// Plants
		protected.POST("/plants", createPlant)
		protected.GET("/plants", getPlants)
		protected.GET("/plants/:id", getPlantByID)
		protected.POST("/plants/generate", generatePlantWithAI)
		protected.POST("/plants/generate-multiple", generateMultiplePlantsHandler)

		// Gardens
		protected.POST("/gardens", createGarden)
		protected.GET("/gardens", listGardens)
		protected.GET("/gardens/:id", getGardenByID)
		protected.PUT("/gardens/:id", updateGarden)
		protected.DELETE("/gardens/:id", deleteGarden)

		// Consents (RGPD)
		protected.POST("/consents", recordConsent)
		protected.GET("/consents", getUserConsents)
		protected.GET("/consents/latest", getLatestUserConsents)

		// Models 3D (USDZ files) - Protected endpoint
		protected.GET("/models/:filename", func(c *gin.Context) {
			filename := c.Param("filename")

			// Sécurité: empêcher les path traversal attacks
			if strings.Contains(filename, "..") || strings.Contains(filename, "/") {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid filename"})
				return
			}

			// Vérifier que c'est bien un fichier .usdz
			if !strings.HasSuffix(strings.ToLower(filename), ".usdz") {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Only .usdz files are allowed"})
				return
			}

			filePath := fmt.Sprintf("./models/%s", filename)

			// Vérifier si le fichier existe
			if _, err := os.Stat(filePath); os.IsNotExist(err) {
				c.JSON(http.StatusNotFound, gin.H{"error": "Model not found"})
				return
			}

			c.Header("Content-Type", "model/vnd.usdz+zip")
			c.File(filePath)
		})
	}

	fmt.Println("🚀 Serveur démarré sur http://localhost:8080")
	if err := router.Run(":8080"); err != nil {
		log.Fatal("❌ Erreur lors du démarrage du serveur :", err) // nolint:misspell
	}

	defer func() {
		if err = client.Disconnect(context.Background()); err != nil {
			log.Fatal("❌ Erreur lors de la déconnexion de MongoDB :", err)
		}
		fmt.Println("🔌 Déconnecté de MongoDB.")
	}()
}
