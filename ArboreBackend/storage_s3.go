package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// Implémentation S3 du StorageProvider (#401 étape 5).
//
// Compatible avec **Cloudflare R2, Amazon S3 et MinIO** : tous parlent le même
// protocole. Le choix du fournisseur est donc une affaire de configuration, pas
// de code.
//
// R2 est le choix retenu pour Arbore, et la raison est structurelle plutôt que
// technique : R2 ne facture **jamais** la sortie. Une app mobile qui télécharge
// des modèles de 121 Mo rend ce poste imprévisible chez un fournisseur qui le
// tarife, et c'est le seul risque financier réel du projet.
//
// Un seul seau, des préfixes par famille — plutôt que trois seaux. Moins de
// configuration à fournir à une machine neuve, et le préfixe suffit à séparer
// les familles.

const (
	s3PrefixModelsLight = "models/"
	s3PrefixModelsHeavy = "models/heavy/"
	s3PrefixThumbnails  = "thumbnails/"
	s3PrefixPhotos      = "photos/"

	// Durée de validité d'une URL signée. Assez longue pour qu'un
	// téléchargement de 121 Mo aboutisse sur une connexion mobile médiocre,
	// assez courte pour qu'une URL fuitée n'ait qu'une valeur passagère.
	s3PresignTTL = 15 * time.Minute
)

type s3Storage struct {
	client *minio.Client
	bucket string
	name   string
}

func newS3Storage() (*s3Storage, error) {
	endpoint := strings.TrimSpace(os.Getenv("STORAGE_S3_ENDPOINT"))
	bucket := strings.TrimSpace(os.Getenv("STORAGE_S3_BUCKET"))
	accessKey := strings.TrimSpace(os.Getenv("STORAGE_S3_ACCESS_KEY"))
	secretKey := strings.TrimSpace(os.Getenv("STORAGE_S3_SECRET_KEY"))
	region := strings.TrimSpace(os.Getenv("STORAGE_S3_REGION"))
	if region == "" {
		// R2 attend « auto » ; S3 et MinIO le tolèrent.
		region = "auto"
	}

	// Échouer au démarrage plutôt que sur la première requête : une
	// configuration incomplète doit se voir immédiatement, pas se manifester
	// par des 500 sur les modèles une fois en service.
	var missing []string
	for name, value := range map[string]string{
		"STORAGE_S3_ENDPOINT":   endpoint,
		"STORAGE_S3_BUCKET":     bucket,
		"STORAGE_S3_ACCESS_KEY": accessKey,
		"STORAGE_S3_SECRET_KEY": secretKey,
	} {
		if value == "" {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("STORAGE_PROVIDER=s3 mais variables manquantes: %s", strings.Join(missing, ", "))
	}

	// TLS par défaut. Le désactiver n'a de sens que pour un MinIO local.
	useSSL := strings.ToLower(strings.TrimSpace(os.Getenv("STORAGE_S3_USE_SSL"))) != "false"

	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure: useSSL,
		Region: region,
	})
	if err != nil {
		return nil, fmt.Errorf("initialisation du client S3: %w", err)
	}

	return &s3Storage{client: client, bucket: bucket, name: "s3(" + endpoint + ")"}, nil
}

func (s *s3Storage) Name() string { return s.name }

// key traduit un objet en clé S3. La validation du nom est refaite ici : le
// support ne doit pas dépendre de la vigilance de ses appelants.
func (s *s3Storage) key(obj StorageObject) (string, error) {
	if obj.Name == "" || strings.ContainsAny(obj.Name, `/\`) || strings.Contains(obj.Name, "..") {
		return "", fmt.Errorf("invalid object name")
	}
	switch obj.Bucket {
	case BucketModelsLight:
		return s3PrefixModelsLight + obj.Name, nil
	case BucketModelsHeavy:
		return s3PrefixModelsHeavy + obj.Name, nil
	case BucketThumbnails:
		return s3PrefixThumbnails + obj.Name, nil
	case BucketPhotos:
		return s3PrefixPhotos + obj.Name, nil
	default:
		return "", fmt.Errorf("unknown bucket %q", obj.Bucket)
	}
}

// isNotFound traduit l'absence côté S3 en ErrObjectNotFound, pour que le
// handler réponde 404 et non 500. Une panne réseau ou un refus
// d'authentification ne doivent PAS passer pour une absence — sinon une
// mauvaise clé d'accès se présenterait comme « tous les modèles ont disparu ».
func isNotFound(err error) bool {
	var resp minio.ErrorResponse
	if errors.As(err, &resp) {
		return resp.Code == "NoSuchKey" || resp.Code == "NoSuchBucket" || resp.StatusCode == 404
	}
	return false
}

func (s *s3Storage) Open(ctx context.Context, obj StorageObject) (io.ReadSeekCloser, ObjectInfo, error) {
	key, err := s.key(obj)
	if err != nil {
		return nil, ObjectInfo{}, err
	}

	object, err := s.client.GetObject(ctx, s.bucket, key, minio.GetObjectOptions{})
	if err != nil {
		if isNotFound(err) {
			return nil, ObjectInfo{}, ErrObjectNotFound
		}
		return nil, ObjectInfo{}, err
	}

	// GetObject est paresseux : l'erreur n'apparaît qu'au premier Stat ou Read.
	// Sans ce Stat, un objet absent produirait une réponse 200 vide.
	stat, err := object.Stat()
	if err != nil {
		_ = object.Close()
		if isNotFound(err) {
			return nil, ObjectInfo{}, ErrObjectNotFound
		}
		return nil, ObjectInfo{}, err
	}

	return object, ObjectInfo{Size: stat.Size, ModTime: stat.LastModified}, nil
}

func (s *s3Storage) Put(ctx context.Context, obj StorageObject, data []byte) error {
	key, err := s.key(obj)
	if err != nil {
		return err
	}
	contentType := "application/octet-stream"
	switch {
	case strings.HasSuffix(strings.ToLower(obj.Name), ".png"):
		contentType = "image/png"
	case strings.HasSuffix(strings.ToLower(obj.Name), ".usdz"):
		contentType = "model/vnd.usdz+zip"
	}
	_, err = s.client.PutObject(ctx, s.bucket, key,
		strings.NewReader(string(data)), int64(len(data)),
		minio.PutObjectOptions{ContentType: contentType})
	return err
}

// PresignedURL est le principal intérêt de ce support : le client télécharge
// directement depuis le stockage, sans faire transiter 121 Mo par le backend.
func (s *s3Storage) PresignedURL(ctx context.Context, obj StorageObject, ttl time.Duration) (string, error) {
	key, err := s.key(obj)
	if err != nil {
		return "", err
	}
	if ttl <= 0 {
		ttl = s3PresignTTL
	}
	u, err := s.client.PresignedGetObject(ctx, s.bucket, key, ttl, nil)
	if err != nil {
		return "", err
	}
	return u.String(), nil
}
