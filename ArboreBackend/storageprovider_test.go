package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// L'abstraction du stockage est sur le chemin de service des assets 3D, dont
// un fichier de 121 Mo. Ces tests portent sur ce qui pourrait mal tourner —
// l'évasion de répertoire et la confusion entre absence et panne — plutôt que
// sur le chemin nominal, trivial.

func newTestStorage(t *testing.T) (*filesystemStorage, string) {
	t.Helper()
	root := t.TempDir()
	fs := &filesystemStorage{
		modelsDir:     filepath.Join(root, "models"),
		heavyDir:      filepath.Join(root, "models", "heavy"),
		thumbnailsDir: filepath.Join(root, "models", "thumbnails"),
	}
	for _, d := range []string{fs.modelsDir, fs.heavyDir, fs.thumbnailsDir} {
		if err := os.MkdirAll(d, 0o750); err != nil {
			t.Fatalf("préparation: %v", err)
		}
	}
	return fs, root
}

// TestStorageRefusesPathEscape est la garde qui compte : `Name` vient d'un
// paramètre d'URL. Même si les handlers valident déjà, une seconde barrière au
// niveau du support protège un futur appelant moins prudent.
func TestStorageRefusesPathEscape(t *testing.T) {
	fs, _ := newTestStorage(t)

	for _, name := range []string{
		"../.env",
		"../../etc/passwd",
		"sub/dir.usdz",
		`..\windows.usdz`,
		"",
	} {
		if _, err := fs.resolve(StorageObject{Bucket: BucketModelsLight, Name: name}); err == nil {
			t.Errorf("resolve(%q) devrait échouer — évasion possible", name)
		}
	}
}

// TestStorageDistinguishesMissingFromFailure : confondre les deux masquerait
// une indisponibilité du stockage derrière un « modèle introuvable », et le
// handler répondrait 404 au lieu de 500.
func TestStorageDistinguishesMissingFromFailure(t *testing.T) {
	fs, _ := newTestStorage(t)

	_, _, err := fs.Open(context.Background(),
		StorageObject{Bucket: BucketModelsLight, Name: "absent.usdz"})
	if !errors.Is(err, ErrObjectNotFound) {
		t.Fatalf("un objet absent doit rendre ErrObjectNotFound, obtenu %v", err)
	}

	// Un bucket inconnu est une erreur de programmation, pas une absence.
	_, _, err = fs.Open(context.Background(),
		StorageObject{Bucket: "inexistant", Name: "x.usdz"})
	if errors.Is(err, ErrObjectNotFound) {
		t.Fatal("un bucket inconnu ne doit PAS passer pour un objet absent")
	}
	if err == nil {
		t.Fatal("un bucket inconnu doit échouer")
	}
}

func TestStorageRoundTrip(t *testing.T) {
	fs, root := newTestStorage(t)
	ctx := context.Background()
	payload := []byte("contenu de vignette")

	obj := StorageObject{Bucket: BucketThumbnails, Name: "plante.png"}
	if err := fs.Put(ctx, obj, payload); err != nil {
		t.Fatalf("Put: %v", err)
	}

	// Écrit au bon endroit, et nulle part ailleurs.
	written := filepath.Join(root, "models", "thumbnails", "plante.png")
	if _, err := os.Stat(written); err != nil {
		t.Fatalf("fichier attendu en %s: %v", written, err)
	}

	reader, info, err := fs.Open(ctx, obj)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() { _ = reader.Close() }()

	if info.Size != int64(len(payload)) {
		t.Errorf("taille = %d, attendu %d", info.Size, len(payload))
	}
	if info.ModTime.IsZero() {
		t.Error("ModTime nulle — http.ServeContent ne pourrait pas gérer les requêtes conditionnelles")
	}
}

// TestStorageOpenIsSeekable verrouille la propriété qui permet les requêtes
// par plage. Sans elle, un téléchargement interrompu de modèle `heavy`
// (jusqu'à 121 Mo) devrait repartir de zéro.
func TestStorageOpenIsSeekable(t *testing.T) {
	fs, _ := newTestStorage(t)
	ctx := context.Background()
	obj := StorageObject{Bucket: BucketModelsLight, Name: "m.usdz"}

	if err := fs.Put(ctx, obj, []byte("0123456789")); err != nil {
		t.Fatalf("Put: %v", err)
	}
	reader, _, err := fs.Open(ctx, obj)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() { _ = reader.Close() }()

	if _, err := reader.Seek(5, 0); err != nil {
		t.Fatalf("Seek doit être possible: %v", err)
	}
	buf := make([]byte, 5)
	if _, err := reader.Read(buf); err != nil {
		t.Fatalf("Read après Seek: %v", err)
	}
	if string(buf) != "56789" {
		t.Errorf("après Seek(5) on attend \"56789\", obtenu %q", buf)
	}
}

// TestFilesystemHasNoPresign : le disque ne sait pas signer d'URL, et doit le
// dire clairement pour que le handler retombe sur le service direct.
func TestFilesystemHasNoPresign(t *testing.T) {
	fs, _ := newTestStorage(t)
	url, err := fs.PresignedURL(context.Background(),
		StorageObject{Bucket: BucketModelsLight, Name: "m.usdz"}, 0)
	if !errors.Is(err, ErrNoPresign) {
		t.Errorf("attendu ErrNoPresign, obtenu %v", err)
	}
	if url != "" {
		t.Errorf("aucune URL ne doit être rendue, obtenu %q", url)
	}
}

// TestInitStorageProviderRejectsUnknown : une valeur inconnue doit faire
// échouer le démarrage plutôt que retomber silencieusement sur le disque —
// sinon une faute de frappe dans STORAGE_PROVIDER servirait les mauvais
// fichiers sans que personne ne s'en aperçoive.
func TestInitStorageProviderRejectsUnknown(t *testing.T) {
	t.Setenv("STORAGE_PROVIDER", "s33")
	if err := initStorageProvider(); err == nil {
		t.Fatal("une valeur inconnue doit être refusée")
	}

	for _, v := range []string{"", "filesystem", "fs", "  FileSystem  "} {
		t.Setenv("STORAGE_PROVIDER", v)
		if err := initStorageProvider(); err != nil {
			t.Errorf("STORAGE_PROVIDER=%q devrait être accepté: %v", v, err)
		}
	}
}
