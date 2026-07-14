package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo/options"

	"ArboreBackend/middleware"
)

const (
	communityPostsCollection = "community_posts"
	communityUploadsURLPath  = "/uploads/community"
	defaultCommunityUploads  = "./uploads/community"
	maxCommunityImageBytes   = 12 << 20 // 12 MB
)

var allowedCommunityPostTypes = map[string]struct{}{
	"before_after": {},
	"dream_garden": {},
	"tips":         {},
}

type Post struct {
	ID          primitive.ObjectID `json:"id" bson:"_id,omitempty"`
	UserID      string             `json:"userId" bson:"userId"`
	Type        string             `json:"type" bson:"type"`
	Title       string             `json:"title" bson:"title"`
	Description string             `json:"description" bson:"description"`
	ImageURL    string             `json:"imageUrl" bson:"imageUrl"`
	LikesCount  int                `json:"likesCount" bson:"likesCount"`
	CreatedAt   time.Time          `json:"createdAt" bson:"createdAt"`
}

func registerCommunityPublicRoutes(router *gin.Engine) {
	router.GET(communityUploadsURLPath+"/:filename", serveCommunityUpload)
}

func registerCommunityProtectedRoutes(router gin.IRoutes) {
	router.GET("/api/v1/community/feed", getCommunityFeed)
	router.POST("/api/v1/community/posts", createCommunityPost)
}

func getCommunityFeed(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 8*time.Second)
	defer cancel()

	opts := options.Find().
		SetSort(bson.D{{Key: "createdAt", Value: -1}}).
		SetLimit(100)

	cursor, err := getDatabaseForRequest(c).
		Collection(communityPostsCollection).
		Find(ctx, bson.M{}, opts)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Impossible de charger le feed communautaire"})
		return
	}
	defer func() {
		_ = cursor.Close(ctx)
	}()

	var posts []Post
	if err := cursor.All(ctx, &posts); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Impossible de décoder le feed communautaire"})
		return
	}
	if posts == nil {
		posts = []Post{}
	}

	c.JSON(http.StatusOK, posts)
}

func createCommunityPost(c *gin.Context) {
	userID := strings.TrimSpace(c.GetString("uid"))
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Utilisateur non authentifié"})
		return
	}

	title := strings.TrimSpace(c.PostForm("title"))
	description := strings.TrimSpace(c.PostForm("description"))
	postType := strings.TrimSpace(c.PostForm("type"))

	if err := validateCommunityPostInput(title, description, postType); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	fileHeader, err := c.FormFile("image")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Image requise"})
		return
	}
	if fileHeader.Size <= 0 || fileHeader.Size > maxCommunityImageBytes {
		c.JSON(http.StatusBadRequest, gin.H{"error": "L'image doit peser moins de 12 MB"})
		return
	}

	imageURL, err := saveCommunityImage(c, fileHeader)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	now := time.Now().UTC()
	post := Post{
		ID:          primitive.NewObjectID(),
		UserID:      userID,
		Type:        postType,
		Title:       title,
		Description: description,
		ImageURL:    imageURL,
		LikesCount:  0,
		CreatedAt:   now,
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 8*time.Second)
	defer cancel()

	dbSelector := c.GetString(middleware.DBSelectorKey)
	_, err = getDatabaseForRequest(c).
		Collection(communityPostsCollection).
		InsertOne(ctx, maybeLabelTestDoc(dbSelector, post))
	if err != nil {
		_ = removeCommunityImageByURL(imageURL)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Impossible de publier le post"})
		return
	}

	c.JSON(http.StatusCreated, post)
}

func validateCommunityPostInput(title, description, postType string) error {
	switch {
	case title == "":
		return newCommunityUserError("Titre requis")
	case len([]rune(title)) > 120:
		return newCommunityUserError("Le titre ne peut pas dépasser 120 caractères")
	case description == "":
		return newCommunityUserError("Description requise")
	case len([]rune(description)) > 1200:
		return newCommunityUserError("La description ne peut pas dépasser 1200 caractères")
	}

	if _, ok := allowedCommunityPostTypes[postType]; !ok {
		return newCommunityUserError("Type de post invalide")
	}

	return nil
}

func saveCommunityImage(c *gin.Context, fileHeader *multipart.FileHeader) (string, error) {
	file, err := fileHeader.Open()
	if err != nil {
		return "", newCommunityUserError("Impossible de lire l'image")
	}
	defer func() {
		_ = file.Close()
	}()

	data, err := io.ReadAll(io.LimitReader(file, maxCommunityImageBytes+1))
	if err != nil {
		return "", newCommunityUserError("Impossible de lire l'image")
	}
	if len(data) == 0 || len(data) > maxCommunityImageBytes {
		return "", newCommunityUserError("L'image doit peser moins de 12 MB")
	}

	contentType := http.DetectContentType(data[:minInt(len(data), 512)])
	extension, err := communityImageExtension(contentType)
	if err != nil {
		return "", err
	}

	uploadDir := communityUploadsDir()
	if err := os.MkdirAll(uploadDir, 0o750); err != nil {
		return "", newCommunityUserError("Impossible de préparer le dossier d'upload")
	}

	filename, err := secureCommunityFilename(extension)
	if err != nil {
		return "", newCommunityUserError("Impossible de générer un nom de fichier")
	}

	destination := filepath.Join(uploadDir, filename)
	if err := os.WriteFile(destination, data, 0o600); err != nil {
		return "", newCommunityUserError("Impossible de sauvegarder l'image")
	}

	return absoluteCommunityImageURL(c, filename), nil
}

func communityImageExtension(contentType string) (string, error) {
	switch contentType {
	case "image/jpeg":
		return ".jpg", nil
	case "image/png":
		return ".png", nil
	default:
		return "", newCommunityUserError("Format d'image non supporté")
	}
}

func newCommunityUserError(message string) error {
	return errors.New(message)
}

func secureCommunityFilename(extension string) (string, error) {
	randomBytes := make([]byte, 12)
	if _, err := rand.Read(randomBytes); err != nil {
		return "", err
	}
	return fmt.Sprintf("%s_%s%s", time.Now().UTC().Format("20060102T150405Z"), hex.EncodeToString(randomBytes), extension), nil
}

func absoluteCommunityImageURL(c *gin.Context, filename string) string {
	scheme := c.GetHeader("X-Forwarded-Proto")
	if scheme == "" {
		if c.Request.TLS != nil {
			scheme = "https"
		} else {
			scheme = "http"
		}
	}

	host := c.GetHeader("X-Forwarded-Host")
	if host == "" {
		host = c.Request.Host
	}

	return fmt.Sprintf("%s://%s%s/%s", scheme, host, communityUploadsURLPath, filename)
}

func serveCommunityUpload(c *gin.Context) {
	filename := c.Param("filename")
	if filename != filepath.Base(filename) || strings.Contains(filename, "..") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Nom de fichier invalide"})
		return
	}

	lower := strings.ToLower(filename)
	if !strings.HasSuffix(lower, ".jpg") && !strings.HasSuffix(lower, ".png") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Extension non supportée"})
		return
	}

	filePath := filepath.Join(communityUploadsDir(), filename)
	if _, err := os.Stat(filePath); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Image introuvable"})
		return
	}

	c.File(filePath)
}

func removeCommunityImageByURL(imageURL string) error {
	parts := strings.Split(imageURL, "/")
	if len(parts) == 0 {
		return nil
	}

	filename := parts[len(parts)-1]
	if filename == "" || filename != filepath.Base(filename) {
		return nil
	}

	return os.Remove(filepath.Join(communityUploadsDir(), filename))
}

func communityUploadsDir() string {
	if value := strings.TrimSpace(os.Getenv("COMMUNITY_UPLOADS_DIR")); value != "" {
		return value
	}
	return defaultCommunityUploads
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}
