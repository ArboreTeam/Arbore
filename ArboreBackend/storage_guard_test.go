package main

import (
	"context"
	"errors"
	"io"
	"sync"
	"testing"
	"time"
)

// Support de test : compte ce qui lui parvient réellement, pour vérifier que
// la garde bloque AVANT d'atteindre le stockage — sinon l'opération serait
// facturée malgré le refus.
type countingStorage struct {
	mu       sync.Mutex
	opens    int
	puts     int
	presigns int
}

func (c *countingStorage) Name() string { return "counting" }

func (c *countingStorage) Open(context.Context, StorageObject) (io.ReadSeekCloser, ObjectInfo, error) {
	c.mu.Lock()
	c.opens++
	c.mu.Unlock()
	return nil, ObjectInfo{}, nil
}

func (c *countingStorage) Put(context.Context, StorageObject, []byte) error {
	c.mu.Lock()
	c.puts++
	c.mu.Unlock()
	return nil
}

func (c *countingStorage) PresignedURL(context.Context, StorageObject, time.Duration) (string, error) {
	c.mu.Lock()
	c.presigns++
	c.mu.Unlock()
	return "https://exemple.invalid/objet", nil
}

func TestGuardStopsAtLimit(t *testing.T) {
	inner := &countingStorage{}
	g := newGuardedStorage(inner, storageGuardConfig{MaxOpsPerWindow: 3, Window: time.Minute})
	obj := StorageObject{Bucket: BucketModelsLight, Name: "m.usdz"}

	for i := range 3 {
		if _, _, err := g.Open(context.Background(), obj); err != nil {
			t.Fatalf("opération %d devrait passer: %v", i+1, err)
		}
	}
	if _, _, err := g.Open(context.Background(), obj); !errors.Is(err, ErrStorageQuotaExceeded) {
		t.Fatalf("la 4e opération devrait être refusée, obtenu %v", err)
	}

	// Point décisif : le support ne doit PAS avoir été sollicité par
	// l'opération refusée, sinon elle serait facturée quand même.
	if inner.opens != 3 {
		t.Errorf("le stockage a reçu %d appels, attendu 3 — la garde laisse passer", inner.opens)
	}
}

func TestGuardResetsAfterWindow(t *testing.T) {
	inner := &countingStorage{}
	g := newGuardedStorage(inner, storageGuardConfig{MaxOpsPerWindow: 1, Window: 40 * time.Millisecond})
	obj := StorageObject{Bucket: BucketModelsLight, Name: "m.usdz"}

	if _, _, err := g.Open(context.Background(), obj); err != nil {
		t.Fatalf("première opération: %v", err)
	}
	if _, _, err := g.Open(context.Background(), obj); !errors.Is(err, ErrStorageQuotaExceeded) {
		t.Fatal("la seconde devrait être refusée dans la même fenêtre")
	}

	time.Sleep(60 * time.Millisecond)
	if _, _, err := g.Open(context.Background(), obj); err != nil {
		t.Fatalf("après la fenêtre, l'opération devrait repasser: %v", err)
	}
}

// TestGuardRejectsOversizedBeforeCountingIt : un objet trop gros ne doit pas
// entamer le budget de la fenêtre. Sinon quelques tentatives d'envoi géant
// bloqueraient tout le trafic légitime.
func TestGuardRejectsOversizedBeforeCountingIt(t *testing.T) {
	inner := &countingStorage{}
	g := newGuardedStorage(inner, storageGuardConfig{
		MaxOpsPerWindow: 2, Window: time.Minute, MaxObjectBytes: 10,
	})
	obj := StorageObject{Bucket: BucketThumbnails, Name: "v.png"}

	for range 5 {
		if err := g.Put(context.Background(), obj, make([]byte, 100)); !errors.Is(err, ErrStorageQuotaExceeded) {
			t.Fatalf("un objet trop gros doit être refusé, obtenu %v", err)
		}
	}
	if inner.puts != 0 {
		t.Errorf("le stockage a reçu %d écritures, attendu 0", inner.puts)
	}

	// Le budget doit être intact : deux écritures valides passent encore.
	for i := range 2 {
		if err := g.Put(context.Background(), obj, []byte("ok")); err != nil {
			t.Fatalf("écriture valide %d refusée — les refus de taille ont consommé le budget: %v", i+1, err)
		}
	}
}

// TestGuardThrottlesPresign verrouille la correction d'un défaut de conception.
//
// Une première version ne décomptait PAS les signatures, au motif qu'elles sont
// calculées localement. C'était confondre le coût de fabriquer la clé avec
// celui d'ouvrir la porte : une URL signée AUTORISE un téléchargement, et ce
// téléchargement est facturé.
//
// Pire, la garde en devenait inerte : avec un support qui sait signer,
// `serveStorageObject` emprunte cette voie et n'appelle jamais `Open` — le seul
// chemin alors compté. Elle n'aurait protégé que le cas où elle était inutile.
func TestGuardThrottlesPresign(t *testing.T) {
	inner := &countingStorage{}
	g := newGuardedStorage(inner, storageGuardConfig{MaxOpsPerWindow: 3, Window: time.Minute})
	obj := StorageObject{Bucket: BucketModelsHeavy, Name: "gros.usdz"}

	for i := range 3 {
		if _, err := g.PresignedURL(context.Background(), obj, 0); err != nil {
			t.Fatalf("signature %d devrait passer: %v", i+1, err)
		}
	}
	if _, err := g.PresignedURL(context.Background(), obj, 0); !errors.Is(err, ErrStorageQuotaExceeded) {
		t.Fatalf("la 4e signature devrait être refusée, obtenu %v", err)
	}
	if inner.presigns != 3 {
		t.Errorf("le support a signé %d fois, attendu 3 — la garde laisse passer", inner.presigns)
	}
}

// TestGuardCountsPresignAndOpenTogether : les deux voies produisent chacune une
// lecture facturée, elles doivent donc puiser au MÊME budget. Les compter
// séparément doublerait l'exposition réelle.
func TestGuardCountsPresignAndOpenTogether(t *testing.T) {
	inner := &countingStorage{}
	g := newGuardedStorage(inner, storageGuardConfig{MaxOpsPerWindow: 2, Window: time.Minute})
	obj := StorageObject{Bucket: BucketModelsLight, Name: "m.usdz"}

	if _, err := g.PresignedURL(context.Background(), obj, 0); err != nil {
		t.Fatalf("signature: %v", err)
	}
	if _, _, err := g.Open(context.Background(), obj); err != nil {
		t.Fatalf("lecture: %v", err)
	}
	// Budget épuisé : les deux voies partagent le compteur.
	if _, err := g.PresignedURL(context.Background(), obj, 0); !errors.Is(err, ErrStorageQuotaExceeded) {
		t.Fatal("signature + lecture doivent puiser au même budget")
	}
}

// Support de test qui NE SAIT PAS signer, comme `filesystemStorage` — celui de
// la production depuis le 2026-10-21.
type unsignableStorage struct {
	countingStorage
}

func (u *unsignableStorage) PresignedURL(context.Context, StorageObject, time.Duration) (string, error) {
	u.mu.Lock()
	u.presigns++
	u.mu.Unlock()
	return "", ErrNoPresign
}

// servir reproduit ce que fait `serveStorageObject` : tenter la voie signée,
// puis retomber sur la lecture directe. C'est le seul enchaînement qui compte,
// puisque c'est celui que chaque requête emprunte.
func servir(t *testing.T, g *guardedStorage, obj StorageObject) error {
	t.Helper()
	if url, err := g.PresignedURL(context.Background(), obj, 15*time.Minute); err == nil && url != "" {
		return nil // redirection : rien d'autre à faire
	} else if errors.Is(err, ErrStorageQuotaExceeded) {
		return err
	}
	_, _, err := g.Open(context.Background(), obj)
	return err
}

// TestGuardSignatureRefuseeNeConsommePasLeBudget verrouille la correction de
// #737.
//
// Une signature qui échoue n'autorise aucun téléchargement. La décompter
// quand même faisait coûter DEUX opérations à un fichier servi sur un support
// incapable de signer, donc divisait par deux le plafond configuré. Mesuré en
// production : `200 op/min` ne laissait passer que 100 vignettes, alors que le
// catalogue en compte 123.
func TestGuardSignatureRefuseeNeConsommePasLeBudget(t *testing.T) {
	inner := &unsignableStorage{}
	g := newGuardedStorage(inner, storageGuardConfig{MaxOpsPerWindow: 1, Window: time.Minute})
	obj := StorageObject{Bucket: BucketThumbnails, Name: "v.png"}

	if _, err := g.PresignedURL(context.Background(), obj, 0); !errors.Is(err, ErrNoPresign) {
		t.Fatalf("un support sans signature doit rendre ErrNoPresign, obtenu %v", err)
	}
	// Le budget doit être INTACT : la signature n'a rien autorisé.
	if _, _, err := g.Open(context.Background(), obj); err != nil {
		t.Fatalf("la lecture devrait passer — la signature refusée a consommé le budget: %v", err)
	}
}

// TestGuardUnFichierServiCoûteUneOperation : l'invariant, exprimé sur le
// chemin réel. Avec un plafond de N, on doit pouvoir servir N fichiers.
func TestGuardUnFichierServiCouteUneOperation(t *testing.T) {
	for _, cas := range []struct {
		nom   string
		inner StorageProvider
	}{
		{"support qui sait signer", &countingStorage{}},
		{"support qui ne sait pas signer", &unsignableStorage{}},
	} {
		t.Run(cas.nom, func(t *testing.T) {
			g := newGuardedStorage(cas.inner, storageGuardConfig{MaxOpsPerWindow: 5, Window: time.Minute})
			obj := StorageObject{Bucket: BucketThumbnails, Name: "v.png"}

			for i := range 5 {
				if err := servir(t, g, obj); err != nil {
					t.Fatalf("fichier %d sur 5 refusé alors que le plafond est 5: %v", i+1, err)
				}
			}
			if err := servir(t, g, obj); !errors.Is(err, ErrStorageQuotaExceeded) {
				t.Fatalf("le 6e devrait être refusé, obtenu %v", err)
			}
		})
	}
}

// TestGuardRefusNEstPasAnnule : un refus de budget ne doit pas se rendre
// lui-même. Sans quoi la garde laisserait passer indéfiniment : chaque refus
// libérerait la place du suivant.
func TestGuardRefusNEstPasAnnule(t *testing.T) {
	inner := &unsignableStorage{}
	g := newGuardedStorage(inner, storageGuardConfig{MaxOpsPerWindow: 1, Window: time.Minute})
	obj := StorageObject{Bucket: BucketThumbnails, Name: "v.png"}

	if err := servir(t, g, obj); err != nil {
		t.Fatalf("premier fichier: %v", err)
	}
	for i := range 3 {
		if err := servir(t, g, obj); !errors.Is(err, ErrStorageQuotaExceeded) {
			t.Fatalf("refus %d attendu, obtenu %v — un refus se rend lui-même", i+1, err)
		}
	}
}

// TestGuardAnnulationNeTraverssePasLaFenetre : une annulation arrivant après un
// basculement de fenêtre ne doit pas décrémenter le compteur de la fenêtre
// suivante, qui n'a rien réservé.
func TestGuardAnnulationNeTraversePasLaFenetre(t *testing.T) {
	g := newGuardedStorage(&unsignableStorage{}, storageGuardConfig{
		MaxOpsPerWindow: 1, Window: 40 * time.Millisecond,
	})

	generation, err := g.allow()
	if err != nil {
		t.Fatalf("réservation: %v", err)
	}
	time.Sleep(60 * time.Millisecond) // la fenêtre bascule

	obj := StorageObject{Bucket: BucketThumbnails, Name: "v.png"}
	if _, _, err := g.Open(context.Background(), obj); err != nil {
		t.Fatalf("première opération de la nouvelle fenêtre: %v", err)
	}
	g.cancel(generation) // annulation tardive : doit être ignorée

	if _, _, err := g.Open(context.Background(), obj); !errors.Is(err, ErrStorageQuotaExceeded) {
		t.Fatal("l'annulation tardive a rendu du budget à une fenêtre qui n'avait rien réservé")
	}
}

func TestGuardDisabledWhenZero(t *testing.T) {
	inner := &countingStorage{}
	g := newGuardedStorage(inner, storageGuardConfig{MaxOpsPerWindow: 0})
	for range 100 {
		if _, _, err := g.Open(context.Background(), StorageObject{Bucket: BucketModelsLight, Name: "m.usdz"}); err != nil {
			t.Fatalf("garde désactivée: aucune opération ne doit être refusée, obtenu %v", err)
		}
	}
}

func TestGuardConfigFromEnv(t *testing.T) {
	t.Setenv("STORAGE_MAX_OPS_PER_MINUTE", "42")
	t.Setenv("STORAGE_MAX_OBJECT_BYTES", "1024")
	cfg := storageGuardFromEnv()
	if cfg.MaxOpsPerWindow != 42 || cfg.MaxObjectBytes != 1024 {
		t.Fatalf("configuration mal lue: %+v", cfg)
	}

	// Une valeur absurde doit retomber sur le défaut plutôt que de désactiver
	// la garde : une faute de frappe ne doit pas ouvrir les vannes.
	t.Setenv("STORAGE_MAX_OPS_PER_MINUTE", "abc")
	if got := storageGuardFromEnv().MaxOpsPerWindow; got != 200 {
		t.Errorf("valeur illisible → défaut attendu 200, obtenu %d", got)
	}
	t.Setenv("STORAGE_MAX_OPS_PER_MINUTE", "-5")
	if got := storageGuardFromEnv().MaxOpsPerWindow; got != 200 {
		t.Errorf("valeur négative → défaut attendu 200, obtenu %d", got)
	}
}
