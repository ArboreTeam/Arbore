package main

import (
	"errors"
	"net/http"
	"strings"
	"testing"

	"github.com/minio/minio-go/v7"
)

// Ces tests ne requièrent aucun serveur S3 : ils portent sur la traduction des
// objets en clés et sur la classification des erreurs, qui sont les deux
// endroits où une faute aurait des conséquences silencieuses.

func TestS3KeyMapping(t *testing.T) {
	s := &s3Storage{bucket: "arbore"}

	cases := map[StorageBucket]string{
		BucketModelsLight: "models/Cactus.usdz",
		BucketModelsHeavy: "models/heavy/Cactus.usdz",
		BucketThumbnails:  "thumbnails/Cactus.usdz",
	}
	for bucket, expected := range cases {
		got, err := s.key(StorageObject{Bucket: bucket, Name: "Cactus.usdz"})
		if err != nil {
			t.Fatalf("key(%s): %v", bucket, err)
		}
		if got != expected {
			t.Errorf("key(%s) = %q, attendu %q", bucket, got, expected)
		}
	}

	// Les préfixes light et heavy ne doivent pas se confondre : `models/` est
	// un préfixe de `models/heavy/`, donc un objet heavy mal traduit
	// atterrirait dans le jeu léger et servirait le mauvais fichier.
	light, _ := s.key(StorageObject{Bucket: BucketModelsLight, Name: "x.usdz"})
	heavy, _ := s.key(StorageObject{Bucket: BucketModelsHeavy, Name: "x.usdz"})
	if light == heavy {
		t.Fatal("light et heavy doivent produire des clés distinctes")
	}
	if strings.HasPrefix(strings.TrimPrefix(light, s3PrefixModelsLight), "heavy/") {
		t.Error("un objet light ne doit pas tomber dans le préfixe heavy")
	}
}

// TestS3KeyRefusesEscape : le support ne doit pas dépendre de la vigilance de
// ses appelants. Même garde que côté disque.
func TestS3KeyRefusesEscape(t *testing.T) {
	s := &s3Storage{bucket: "arbore"}
	for _, name := range []string{"", "../secret", "sub/dir.usdz", `..\x.usdz`, "a/b"} {
		if _, err := s.key(StorageObject{Bucket: BucketModelsLight, Name: name}); err == nil {
			t.Errorf("key(%q) devrait échouer", name)
		}
	}
	if _, err := s.key(StorageObject{Bucket: "inconnu", Name: "x.usdz"}); err == nil {
		t.Error("un bucket inconnu doit échouer")
	}
}

// TestS3NotFoundClassification est la garde la plus importante de ce support.
//
// Confondre « objet absent » et « stockage inaccessible » ferait répondre 404
// à une panne : une clé d'accès expirée se présenterait comme « tous les
// modèles ont disparu », et personne n'irait chercher la vraie cause.
func TestS3NotFoundClassification(t *testing.T) {
	absents := []error{
		minio.ErrorResponse{Code: "NoSuchKey"},
		minio.ErrorResponse{Code: "NoSuchBucket"},
		minio.ErrorResponse{StatusCode: http.StatusNotFound},
	}
	for _, err := range absents {
		if !isNotFound(err) {
			t.Errorf("%v devrait être classée comme absence", err)
		}
	}

	pannes := []error{
		minio.ErrorResponse{Code: "AccessDenied", StatusCode: http.StatusForbidden},
		minio.ErrorResponse{Code: "InvalidAccessKeyId", StatusCode: http.StatusForbidden},
		minio.ErrorResponse{Code: "InternalError", StatusCode: http.StatusInternalServerError},
		errors.New("connexion réseau interrompue"),
	}
	for _, err := range pannes {
		if isNotFound(err) {
			t.Errorf("%v ne doit PAS passer pour une absence — le handler répondrait 404 sur une panne", err)
		}
	}
}

// TestS3RefusesIncompleteConfig : échouer au démarrage plutôt qu'à la première
// requête. Une configuration partielle doit se voir immédiatement, pas se
// manifester par des 500 sur les modèles une fois en service.
func TestS3RefusesIncompleteConfig(t *testing.T) {
	t.Setenv("STORAGE_PROVIDER", "r2")
	for _, v := range []string{"STORAGE_S3_ENDPOINT", "STORAGE_S3_BUCKET", "STORAGE_S3_ACCESS_KEY", "STORAGE_S3_SECRET_KEY"} {
		t.Setenv(v, "")
	}
	err := initStorageProvider()
	if err == nil {
		t.Fatal("une configuration incomplète doit faire échouer le démarrage")
	}
	// Le message doit NOMMER ce qui manque : un « configuration invalide » sec
	// obligerait à lire le code pour savoir quoi fournir.
	for _, v := range []string{"STORAGE_S3_ENDPOINT", "STORAGE_S3_BUCKET"} {
		if !strings.Contains(err.Error(), v) {
			t.Errorf("le message d'erreur devrait nommer %s, obtenu: %v", v, err)
		}
	}
}
