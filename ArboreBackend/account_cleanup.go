package main

import (
	"context"
	"os"
	"path/filepath"
	"strings"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

// deleteLegacyCommunityData only exists to honour account deletion for data
// created by older TestFlight builds. No community route is registered.
func deleteLegacyCommunityData(ctx context.Context, db *mongo.Database, uid string) (int64, error) {
	collection := db.Collection("community_posts")
	cursor, err := collection.Find(ctx, bson.M{"userId": uid})
	if err != nil {
		return 0, err
	}
	defer func() {
		_ = cursor.Close(ctx)
	}()

	var posts []struct {
		ImageURL string `bson:"imageUrl"`
	}
	if err := cursor.All(ctx, &posts); err != nil {
		return 0, err
	}

	result, err := collection.DeleteMany(ctx, bson.M{"userId": uid})
	if err != nil {
		return 0, err
	}
	for _, post := range posts {
		removeLegacyCommunityImage(post.ImageURL)
	}
	return result.DeletedCount, nil
}

func removeLegacyCommunityImage(imageURL string) {
	filename := filepath.Base(strings.TrimSpace(imageURL))
	if filename == "" || filename == "." || filename == string(filepath.Separator) {
		return
	}
	lower := strings.ToLower(filename)
	if !strings.HasSuffix(lower, ".jpg") && !strings.HasSuffix(lower, ".png") {
		return
	}
	directory := strings.TrimSpace(os.Getenv("COMMUNITY_UPLOADS_DIR"))
	if directory == "" {
		directory = "./uploads/community"
	}
	baseDirectory, err := filepath.Abs(directory)
	if err != nil {
		return
	}
	targetPath := filepath.Join(baseDirectory, filename)
	relativePath, err := filepath.Rel(baseDirectory, targetPath)
	if err != nil || relativePath == "." || filepath.IsAbs(relativePath) ||
		relativePath == ".." || strings.HasPrefix(relativePath, ".."+string(filepath.Separator)) {
		return
	}
	// filename is reduced to a basename, extension-whitelisted, and targetPath
	// is proven to remain inside baseDirectory above.
	_ = os.Remove(targetPath) //nolint:gosec
}
