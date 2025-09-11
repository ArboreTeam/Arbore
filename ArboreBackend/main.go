package main

import (
	"bytes"
	"context"
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
	UID       string `json:"uid"`
	Email     string `json:"email"`
	Name      string `json:"name"`
	CreatedAt string `json:"createdAt"`
}

type Plant struct {
	ID               primitive.ObjectID           `bson:"_id,omitempty" json:"id"`
	Name             string                       `json:"name"`
	Type             string                       `json:"type"`
	ImageURLs        []string                     `json:"imageURLs"`
	Description      string                       `json:"description"`
	SoilType         string                       `json:"soilType"`
	Exposure         string                       `json:"exposure"`
	WateringNeeds    string                       `json:"wateringNeeds"`
	Temperature      string                       `json:"temperature"`
	Floraison        string                       `json:"floraison"`
	Origin           string                       `json:"origin"`
	WateringReminder string                       `json:"wateringReminder"`
	CareTips         []string                     `json:"careTips"`
	ModelURL         string                       `json:"modelURL" bson:"modelURL"`
	Translations     map[string]map[string]string `json:"translations" bson:"translations"`
}

type AIRequest struct {
	Name string `json:"name"`
}

type AIResponse struct {
	FR map[string]string `json:"fr"`
	EN map[string]string `json:"en"`
	ES map[string]string `json:"es"`
	DE map[string]string `json:"de"`
}

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

func generatePlantWithAI(c *gin.Context) {
	var req AIRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	collection := client.Database("arbore").Collection("plants")

	filter := bson.M{
		"name": bson.M{"$regex": primitive.Regex{Pattern: "^" + req.Name + "$", Options: "i"}},
	}
	var existing Plant
	err := collection.FindOne(context.Background(), filter).Decode(&existing)
	if err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "🌿 Cette plante existe déjà."})
		return
	} else if err != mongo.ErrNoDocuments {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la vérification de l'existence de la plante"})
		return
	}

	jsonData, _ := json.Marshal(req)
	resp, err := http.Post("http://localhost:8001/generate", "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		log.Println("Erreur appel API IA:", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de l'appel à l'IA"})
		return
	}
	defer resp.Body.Close()
	bodyBytes, _ := ioutil.ReadAll(resp.Body)

	var aiResponse AIResponse
	err = json.Unmarshal(bodyBytes, &aiResponse)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors du parsing de la réponse IA"})
		return
	}

	imageURLs := fetchUnsplashImageURLs(req.Name, 3)

	plant := Plant{
		ID:               primitive.NewObjectID(),
		Name:             req.Name,
		Type:             aiResponse.FR["type"],
		ImageURLs:        imageURLs,
		Description:      aiResponse.FR["description"],
		SoilType:         aiResponse.FR["sol"],
		Exposure:         aiResponse.FR["lumière"],
		WateringNeeds:    aiResponse.FR["arrosage"],
		Temperature:      aiResponse.FR["température"],
		Floraison:        aiResponse.FR["floraison"],
		Origin:           aiResponse.FR["origine"],
		WateringReminder: aiResponse.FR["arrosage_frequence"],
		CareTips:         []string{aiResponse.FR["conseils"]},
		ModelURL:         "",
		Translations: map[string]map[string]string{
			"fr": aiResponse.FR,
			"en": aiResponse.EN,
			"es": aiResponse.ES,
			"de": aiResponse.DE,
		},
	}

	plant.SetDefaults()
	_, err = collection.InsertOne(context.Background(), plant)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de l'insertion de la plante générée"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Plante générée et enregistrée avec succès 🌿", "plant": plant})
}

func generateMultiplePlantsHandler(c *gin.Context) {
	var req struct {
		Names []string `json:"names"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Requête invalide"})
		return
	}

	collection := client.Database("arbore").Collection("plants")

	var created []Plant
	var skipped []string

	for _, name := range req.Names {
		name = strings.TrimSpace(name)
		if name == "" {
			continue
		}

		filter := bson.M{
			"name": bson.M{"$regex": primitive.Regex{Pattern: "^" + name + "$", Options: "i"}},
		}

		var existing Plant
		err := collection.FindOne(context.Background(), filter).Decode(&existing)
		if err == nil {
			skipped = append(skipped, name)
			continue
		} else if err != mongo.ErrNoDocuments {
			skipped = append(skipped, name)
			continue
		}

		jsonData, _ := json.Marshal(AIRequest{Name: name})
		resp, err := http.Post("http://localhost:8001/generate", "application/json", bytes.NewBuffer(jsonData))
		if err != nil {
			log.Println("❌ Erreur IA pour", name, ":", err)
			skipped = append(skipped, name)
			continue
		}

		body, _ := ioutil.ReadAll(resp.Body)
		resp.Body.Close()

		var aiResponse AIResponse
		err = json.Unmarshal(body, &aiResponse)
		if err != nil {
			log.Println("❌ Erreur JSON IA pour", name, ":", err)
			skipped = append(skipped, name)
			continue
		}

		imageURLs := fetchUnsplashImageURLs(name, 3)

		plant := Plant{
			ID:               primitive.NewObjectID(),
			Name:             name,
			Type:             aiResponse.FR["type"],
			ImageURLs:        imageURLs,
			Description:      aiResponse.FR["description"],
			SoilType:         aiResponse.FR["sol"],
			Exposure:         aiResponse.FR["lumière"],
			WateringNeeds:    aiResponse.FR["arrosage"],
			Temperature:      aiResponse.FR["température"],
			Floraison:        aiResponse.FR["floraison"],
			Origin:           aiResponse.FR["origine"],
			WateringReminder: aiResponse.FR["arrosage_frequence"],
			CareTips:         []string{aiResponse.FR["conseils"]},
			ModelURL:         "",
			Translations: map[string]map[string]string{
				"fr": aiResponse.FR,
				"en": aiResponse.EN,
				"es": aiResponse.ES,
				"de": aiResponse.DE,
			},
		}

		plant.SetDefaults()
		_, err = collection.InsertOne(context.Background(), plant)
		if err != nil {
			log.Println("❌ Erreur MongoDB insertion:", err)
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

	router.DELETE("/users/:uid", deleteUser)
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
