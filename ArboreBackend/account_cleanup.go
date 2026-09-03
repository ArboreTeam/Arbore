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

// --- Purge Mongo d'un uid, partagée par la suppression de compte et le job ---
//
// `deleteUser` (RGPD Art. 17) et la réconciliation Firebase ↔ Mongo (#393)
// doivent effacer exactement la même chose. Deux implémentations divergeraient
// dès l'ajout d'une collection, et le job laisserait derrière lui des données
// personnelles sans propriétaire — précisément ce qu'il est censé supprimer.
// Une seule définition de « effacer l'empreinte Mongo d'un uid ».
//
// N'inclut ni la révocation Apple ni la suppression de l'identité Firebase :
// la première n'a de sens que sur demande de l'utilisateur, la seconde est
// déjà faite (côté job) ou traitée à part (côté handler).

// purgeCounts détaille ce qui a été supprimé, par collection.
type purgeCounts struct {
	Gardens     int64
	Consents    int64
	LegacyPosts int64
	Users       int64
}

// purgeStepError nomme la collection qui a échoué, pour que l'appelant puisse
// restituer un message précis sans dupliquer la séquence de suppression.
type purgeStepError struct {
	Step string
	Err  error
}

func (e *purgeStepError) Error() string { return e.Step + ": " + e.Err.Error() }
func (e *purgeStepError) Unwrap() error { return e.Err }

// purgeUserData efface toute l'empreinte Mongo d'un uid.
//
// L'ordre suit celui de `deleteUser` : les données rattachées d'abord, le
// document utilisateur en dernier. Si une étape échoue, les précédentes restent
// acquises — les suppressions sont idempotentes, un rejeu reprend proprement.
//
// `users` utilise DeleteMany et non DeleteOne : tant que des comptes portent
// plusieurs documents (audit #338 constat 1), DeleteOne laissait un reliquat
// avec email, nom et photo.
func purgeUserData(ctx context.Context, db *mongo.Database, uid string) (purgeCounts, error) {
	var counts purgeCounts

	gardens, err := db.Collection("gardens").DeleteMany(ctx, bson.M{"uid": uid})
	if err != nil {
		return counts, &purgeStepError{Step: "gardens", Err: err}
	}
	counts.Gardens = gardens.DeletedCount

	consents, err := db.Collection("consents").DeleteMany(ctx, bson.M{"uid": uid})
	if err != nil {
		return counts, &purgeStepError{Step: "consents", Err: err}
	}
	counts.Consents = consents.DeletedCount

	legacyPosts, err := deleteLegacyCommunityData(ctx, db, uid)
	if err != nil {
		return counts, &purgeStepError{Step: "legacy_posts", Err: err}
	}
	counts.LegacyPosts = legacyPosts

	users, err := db.Collection("users").DeleteMany(ctx, bson.M{"uid": uid})
	if err != nil {
		return counts, &purgeStepError{Step: "users", Err: err}
	}
	counts.Users = users.DeletedCount

	return counts, nil
}
