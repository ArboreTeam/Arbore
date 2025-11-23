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

type Plant struct {
    ID               primitive.ObjectID           `bson:"_id,omitempty" json:"id"`
    Name             string                       `json:"name" bson:"name"`
    Type             string                       `json:"type" bson:"type"`
    ImageURLs        []string                     `json:"imageURLs" bson:"imageURLs"`
    Description      string                       `json:"description" bson:"description"`
    SoilType         string                       `json:"soilType" bson:"soilType"`
    Exposure         string                       `json:"exposure" bson:"exposure"`
    WateringNeeds    string                       `json:"wateringNeeds" bson:"wateringNeeds"`
    Temperature      string                       `json:"temperature" bson:"temperature"`
    Floraison        string                       `json:"floraison" bson:"floraison"`
    Origin           string                       `json:"origin" bson:"origin"`
    WateringReminder string                       `json:"wateringReminder" bson:"wateringReminder"`
    CareTips         []string                     `json:"careTips" bson:"careTips"`
    ModelURL         string                       `json:"modelURL" bson:"modelURL"`
    Translations     map[string]map[string]string `json:"translations" bson:"translations"`
}

// Réponse du microservice IA
type AIResponse struct {
    FR map[string]string `json:"fr"`
    EN map[string]string `json:"en"`
    ES map[string]string `json:"es"`
    DE map[string]string `json:"de"`
}

// ---------- petit helper pour le plan A ----------

func safeLangMap(m map[string]string) map[string]string {
    if m == nil {
        return map[string]string{}
    }
    return m
}

// ======================== USERS ========================

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

// Upload photo utilisateur
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

// Return raw image bytes for a user (GET /users/:uid/photo)
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

// ======================== PLANTS ========================

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

// ======================== IA GENERATION ========================

type AIRequest struct {
    Name string `json:"name"`
}

func generatePlantWithAI(c *gin.Context) {
    var req AIRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    collection := client.Database("arbore").Collection("plants")

    // Vérifie si la plante existe déjà (nom insensible à la casse)
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

    // ---- Appel au microservice IA ----
    jsonData, _ := json.Marshal(req)
    resp, err := http.Post("http://localhost:8001/generate", "application/json", bytes.NewBuffer(jsonData))
    if err != nil {
        log.Println("❌ Erreur appel API IA:", err)
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de l'appel à l'IA"})
        return
    }
    defer resp.Body.Close()
    bodyBytes, _ := ioutil.ReadAll(resp.Body)

    // 1️⃣ On vérifie le status HTTP
    if resp.StatusCode != http.StatusOK {
        log.Printf("❌ IA renvoie le status %d, body: %s\n", resp.StatusCode, string(bodyBytes))
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors du traitement IA"})
        return
    }

    // 2️⃣ On parse dans AIResponse
    var aiResponse AIResponse
    err = json.Unmarshal(bodyBytes, &aiResponse)
    if err != nil {
        log.Println("❌ Erreur JSON IA:", err, "body:", string(bodyBytes))
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors du parsing de la réponse IA"})
        return
    }

    // 3️⃣ On s'assure que les maps ne sont jamais nil
    if aiResponse.FR == nil {
        aiResponse.FR = map[string]string{}
    }
    if aiResponse.EN == nil {
        aiResponse.EN = map[string]string{}
    }
    if aiResponse.ES == nil {
        aiResponse.ES = map[string]string{}
    }
    if aiResponse.DE == nil {
        aiResponse.DE = map[string]string{}
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
            log.Println("❌ Erreur JSON IA pour", name, ":", err, "payload:", string(body))
            skipped = append(skipped, name)
            continue
        }

        // 🔒 Plan A ici aussi
        fr := safeLangMap(aiResponse.FR)
        en := safeLangMap(aiResponse.EN)
        es := safeLangMap(aiResponse.ES)
        de := safeLangMap(aiResponse.DE)

        imageURLs := fetchUnsplashImageURLs(name, 3)

        plant := Plant{
            ID:               primitive.NewObjectID(),
            Name:             name,
            Type:             fr["type"],
            ImageURLs:        imageURLs,
            Description:      fr["description"],
            SoilType:         fr["sol"],
            Exposure:         fr["lumière"],
            WateringNeeds:    fr["arrosage"],
            Temperature:      fr["température"],
            Floraison:        fr["floraison"],
            Origin:           fr["origine"],
            WateringReminder: fr["arrosage_frequence"],
            CareTips:         []string{fr["conseils"]},
            ModelURL:         "",
            Translations: map[string]map[string]string{
                "fr": fr,
                "en": en,
                "es": es,
                "de": de,
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

// ======================== MAIN ========================

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
