package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// Abstraction du stockage des assets 3D (issue #401, étape 5).
//
// Même objectif que `llmprovider.go` : couplage faible, cohésion forte. Les
// handlers manipulent des types NEUTRES et une interface stable
// `StorageProvider` ; ils ignorent tout du support concret. Changer de support
// (disque local, MinIO, stockage objet distant) = ajouter une implémentation,
// sans toucher aux handlers.
//
// Ce que l'abstraction préserve, et qui a guidé sa forme :
//
//   - **Les requêtes par plage.** Un modèle `heavy` atteint 121 Mo ; l'app iOS
//     doit pouvoir reprendre un téléchargement interrompu. `Open` rend donc un
//     `io.ReadSeekCloser`, ce qui permet à `http.ServeContent` de gérer les
//     en-têtes `Range` comme le faisait `c.File()`.
//   - **La redirection.** Un stockage objet sert bien mieux ses fichiers
//     lui-même que via un proxy. `PresignedURL` permet à une implémentation de
//     rendre une URL signée ; le handler redirige alors au lieu de relayer les
//     octets. Une implémentation qui ne sait pas le faire rend `ErrNoPresign`,
//     et le handler retombe sur le service direct.

// StorageBucket désigne une famille d'objets, indépendamment de son emplacement.
type StorageBucket string

const (
	BucketModelsLight StorageBucket = "models-light"
	BucketModelsHeavy StorageBucket = "models-heavy"
	BucketThumbnails  StorageBucket = "thumbnails"
)

// StorageObject identifie un objet. `Name` est un nom de fichier simple, déjà
// validé par l'appelant : ni séparateur, ni `..`.
type StorageObject struct {
	Bucket StorageBucket
	Name   string
}

// ObjectInfo porte ce dont `http.ServeContent` a besoin.
type ObjectInfo struct {
	Size    int64
	ModTime time.Time
}

// ErrObjectNotFound distingue l'absence d'un objet d'une panne du support.
// Le handler doit répondre 404 dans le premier cas, 500 dans le second — les
// confondre masquerait une indisponibilité derrière un « modèle introuvable ».
var ErrObjectNotFound = fmt.Errorf("object not found")

// ErrNoPresign indique qu'une implémentation ne sait pas produire d'URL signée.
var ErrNoPresign = fmt.Errorf("presigned URLs not supported by this provider")

type StorageProvider interface {
	// Name identifie l'implémentation dans les journaux.
	Name() string

	// Open rend un lecteur positionnable. L'appelant DOIT le fermer.
	Open(ctx context.Context, obj StorageObject) (io.ReadSeekCloser, ObjectInfo, error)

	// Put écrit un objet. Utilisé par le téléversement de vignettes.
	Put(ctx context.Context, obj StorageObject, data []byte) error

	// PresignedURL rend une URL de téléchargement direct, ou ErrNoPresign.
	PresignedURL(ctx context.Context, obj StorageObject, ttl time.Duration) (string, error)
}

// ─── Implémentation disque ────────────────────────────────────────────────
//
// Reproduit exactement le comportement antérieur à cette abstraction :
// `./models`, `./models/heavy`, et `THUMBNAILS_DIR` avec `./models/thumbnails`
// par défaut.

type filesystemStorage struct {
	modelsDir     string
	heavyDir      string
	thumbnailsDir string
}

func newFilesystemStorage() *filesystemStorage {
	thumbs := strings.TrimSpace(os.Getenv("THUMBNAILS_DIR"))
	if thumbs == "" {
		thumbs = "./models/thumbnails"
	}
	return &filesystemStorage{
		modelsDir:     "./models",
		heavyDir:      "./models/heavy",
		thumbnailsDir: thumbs,
	}
}

func (f *filesystemStorage) Name() string { return "filesystem" }

// resolve traduit un objet en chemin, et REFUSE tout nom qui s'échapperait du
// répertoire de base. La validation côté handler est déjà stricte ; celle-ci
// est une seconde barrière, au cas où un futur appelant serait moins prudent.
func (f *filesystemStorage) resolve(obj StorageObject) (string, error) {
	var baseDir string
	switch obj.Bucket {
	case BucketModelsLight:
		baseDir = f.modelsDir
	case BucketModelsHeavy:
		baseDir = f.heavyDir
	case BucketThumbnails:
		baseDir = f.thumbnailsDir
	default:
		return "", fmt.Errorf("unknown bucket %q", obj.Bucket)
	}

	if obj.Name == "" || strings.ContainsAny(obj.Name, `/\`) || strings.Contains(obj.Name, "..") {
		return "", fmt.Errorf("invalid object name")
	}

	absBase, err := filepath.Abs(baseDir)
	if err != nil {
		return "", err
	}
	target := filepath.Join(absBase, obj.Name)
	rel, err := filepath.Rel(absBase, target)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("path escapes base directory")
	}
	return target, nil
}

func (f *filesystemStorage) Open(_ context.Context, obj StorageObject) (io.ReadSeekCloser, ObjectInfo, error) {
	path, err := f.resolve(obj)
	if err != nil {
		return nil, ObjectInfo{}, err
	}
	// nolint:gosec // `resolve` prouve que le chemin reste sous le répertoire de base.
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, ObjectInfo{}, ErrObjectNotFound
		}
		return nil, ObjectInfo{}, err
	}
	stat, err := file.Stat()
	if err != nil {
		_ = file.Close()
		return nil, ObjectInfo{}, err
	}
	return file, ObjectInfo{Size: stat.Size(), ModTime: stat.ModTime()}, nil
}

func (f *filesystemStorage) Put(_ context.Context, obj StorageObject, data []byte) error {
	path, err := f.resolve(obj)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}

func (f *filesystemStorage) PresignedURL(context.Context, StorageObject, time.Duration) (string, error) {
	return "", ErrNoPresign
}

// ─── Sélection ────────────────────────────────────────────────────────────

// Valeur par défaut plutôt que `nil` : `initStorageProvider` n'est appelée que
// depuis `main()`, or les tests construisent le routeur sans passer par lui. Un
// handler atteint dans ce contexte paniquerait sur un pointeur nul — ce qui
// transformerait un test de routage en panique obscure.
var storage StorageProvider = newFilesystemStorage()

// initStorageProvider choisit l'implémentation. `filesystem` par défaut : tant
// qu'aucun stockage objet n'est configuré, le comportement reste celui d'avant
// cette abstraction.
func initStorageProvider() error {
	var provider StorageProvider

	switch strings.ToLower(strings.TrimSpace(os.Getenv("STORAGE_PROVIDER"))) {
	case "", "filesystem", "fs":
		provider = newFilesystemStorage()
	case "s3", "r2", "minio":
		// Un seul support pour les trois : ils parlent le même protocole. Le
		// choix du fournisseur est une affaire de configuration.
		s3, err := newS3Storage()
		if err != nil {
			return err
		}
		provider = s3
	default:
		return fmt.Errorf("STORAGE_PROVIDER inconnu: %q (valeurs acceptées: filesystem, s3, r2, minio)",
			os.Getenv("STORAGE_PROVIDER"))
	}

	// La garde s'applique à TOUS les supports, pas seulement à ceux qui sont
	// facturés. Un emballement sur le disque local n'est pas gratuit non plus :
	// il sature les entrées-sorties et masque le défaut qui le provoque. Un
	// comportement uniforme est par ailleurs plus simple à raisonner qu'une
	// garde qui n'existerait que dans certaines configurations.
	//
	// Les seuils se règlent par environnement : plus élevés sur un MinIO local,
	// où l'opération ne coûte rien, que sur R2 en production.
	guard := storageGuardFromEnv()
	storage = newGuardedStorage(provider, guard)
	log.Printf("🛡️  Garde stockage (%s) : %d op/min, objet max %d Mio",
		provider.Name(), guard.MaxOpsPerWindow, guard.MaxObjectBytes>>20)

	return nil
}

// ─── Service HTTP ─────────────────────────────────────────────────────────

// serveStorageObject écrit un objet dans la réponse, ou redirige vers lui.
//
// Deux chemins, dans cet ordre :
//
//  1. Si le support sait produire une URL signée, on REDIRIGE. Un stockage
//     objet sert ses fichiers bien mieux qu'un proxy, et cela évite de faire
//     transiter 121 Mo par le backend.
//  2. Sinon on sert directement via `http.ServeContent`, qui honore les
//     en-têtes `Range` — indispensable pour qu'un téléchargement interrompu
//     puisse reprendre, ce que `c.File()` assurait jusqu'ici.
//
// L'absence (404) est distinguée de la panne (500) : les confondre masquerait
// une indisponibilité du stockage derrière un « fichier introuvable ».
func serveStorageObject(c *gin.Context, obj StorageObject, contentType string, notFoundMsg string) {
	ctx := c.Request.Context()

	if url, err := storage.PresignedURL(ctx, obj, 15*time.Minute); err == nil && url != "" {
		c.Redirect(http.StatusFound, url)
		return
	}

	reader, info, err := storage.Open(ctx, obj)
	if err != nil {
		if errors.Is(err, ErrObjectNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": notFoundMsg})
			return
		}
		// La garde a mordu : le fichier existe, c'est nous qui refusons. Un 404
		// laisserait croire à une absence et enverrait chercher au mauvais
		// endroit ; un 503 dit qu'il faut réessayer.
		if errors.Is(err, ErrStorageQuotaExceeded) {
			c.Header("Retry-After", "60")
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"error": "Storage temporarily rate-limited",
				"code":  "STORAGE_RATE_LIMITED",
			})
			return
		}
		log.Printf("❌ stockage (%s) indisponible pour %s/%s : %v", storage.Name(), obj.Bucket, obj.Name, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Storage unavailable"})
		return
	}
	defer func() { _ = reader.Close() }()

	c.Header("Content-Type", contentType)
	http.ServeContent(c.Writer, c.Request, obj.Name, info.ModTime, reader)
}
