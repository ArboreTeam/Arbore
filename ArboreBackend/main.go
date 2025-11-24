// main.go

package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

var client *mongo.Client

type User struct {
	UID              string `json:"uid" bson:"uid"`
	Email            string `json:"email" bson:"email"`
	Name             string `json:"name" bson:"name"`
	CreatedAt        string `json:"createdAt" bson:"createdAt"`
	PhotoData        string `json:"photoData,omitempty" bson:"photoData,omitempty"`
	PhotoContentType string `json:"photoContentType,omitempty" bson:"photoContentType,omitempty"`
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
	Description string        `json:"description" bson:"description"`
	PlantType   string        `json:"plantType" bson:"plantType"`
	Sun         SunInfo       `json:"sun" bson:"sun"`
	Water       WaterInfo     `json:"water" bson:"water"`
	SoilAndPot  SoilAndPotInfo`json:"soilAndPot" bson:"soilAndPot"`
	Health      HealthInfo    `json:"health" bson:"health"`
	LifeCycle   LifeCycleInfo `json:"lifeCycle" bson:"lifeCycle"`
	Care        CareInfo      `json:"care" bson:"care"`
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

// ---------- USERS ----------

func createUser(c *gin.Context) {
	var user User
	if err := c.ShouldBindJSON(&user); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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
	uid := c.Param("uid")
	collection := client.Database("arbore").Collection("users")
	res, err := collection.DeleteOne(context.Background(), bson.M{"uid": uid})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la suppression de l'utilisateur"})
		return
	}

	if res.DeletedCount == 0 {
		c.JSON(http.StatusNotFound, gin.H{"message": "Aucun utilisateur trouvé avec ce UID"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Utilisateur supprimé avec succès"})
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la récupération des plantes"})
		return
	}
	defer cursor.Close(context.Background())

	var plants []Plant
	if err := cursor.All(context.Background(), &plants); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors du décodage des plantes"})
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
	defer resp.Body.Close()

	bodyBytes, _ := ioutil.ReadAll(resp.Body)
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

	// plant.SetDefaults() // si tu remets ça plus tard

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
	uid := c.Param("uid")

	file, header, err := c.Request.FormFile("photo")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "photo not provided or invalid"})
		return
	}
	defer file.Close()

	imageBytes, err := ioutil.ReadAll(file)
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
	filter := bson.M{"uid": uid}
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
	uid := c.Param("uid")
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

// ---------- MAIN ----------

func main() {
	uri := "mongodb+srv://hugorath1234:hugopapa@arbore.cew6l.mongodb.net/arbore?retryWrites=true&w=majority&appName=Arbore"
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

	router := gin.Default()

	// Users
	router.POST("/users", createUser)
	router.GET("/users/:uid", func(c *gin.Context) {
		uid := c.Param("uid")

		var user User
		collection := client.Database("arbore").Collection("users")
		err := collection.FindOne(context.Background(), bson.M{"uid": uid}).Decode(&user)
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

	router.POST("/users/:uid/photo", uploadUserPhoto)
	router.GET("/users/:uid/photo", getUserPhoto)

	router.DELETE("/users/:uid", deleteUser)

	// Plants
	router.POST("/plants", createPlant)
	router.GET("/plants", getPlants)
	router.GET("/plants/:id", getPlantByID)
	router.POST("/plants/generate", generatePlantWithAI)
	router.POST("/plants/generate-multiple", generateMultiplePlantsHandler)

	fmt.Println("🚀 Serveur démarré sur http://localhost:8080")
	if err := router.Run(":8080"); err != nil {
		log.Fatal("❌ Erreur lors du démarrage du serveur :", err)
	}

	defer func() {
		if err = client.Disconnect(context.Background()); err != nil {
			log.Fatal("❌ Erreur lors de la déconnexion de MongoDB :", err)
		}
		fmt.Println("🔌 Déconnecté de MongoDB.")
	}()
}
