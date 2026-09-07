package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Garde-fou sur le stockage externe (#401).
//
// R2, S3 et MinIO facturent à l'opération et au volume. Un défaut applicatif —
// une boucle, un client qui réessaie sans relâche — peut donc coûter de
// l'argent réel sans qu'aucune alerte n'ait le temps de partir.
//
// `guardedStorage` encapsule toute implémentation de `StorageProvider` et
// refuse au-delà de seuils configurés. Le décorateur ne sait rien du support
// concret : la même garde protège R2 en production, MinIO en développement, et
// le disque local.
//
// Elle s'applique à TOUS les supports, pas seulement à ceux qui facturent. Un
// emballement sur disque n'est pas gratuit non plus : il sature les entrées-
// sorties et masque le défaut qui le provoque. Les seuils se règlent par
// environnement — plus élevés là où l'opération ne coûte rien.
//
// Ce que la garde protège, et ce qu'elle ne protège PAS
// ------------------------------------------------------
// Elle borne ce que le BACKEND demande au stockage. Elle ne borne pas les
// téléchargements que les clients font directement via URL signée — ceux-là
// sont bornés en amont, chaque URL exigeant une requête authentifiée au
// backend, elle-même limitée par `apiLimiter`.
//
// Le compteur est en mémoire, donc par processus et remis à zéro au
// redémarrage. C'est un filet contre l'emballement, pas une comptabilité.

type storageGuardConfig struct {
	// MaxOpsPerWindow borne le nombre d'opérations sur la fenêtre. 0 = illimité.
	MaxOpsPerWindow int
	Window          time.Duration
	// MaxObjectBytes borne la taille d'un objet écrit. 0 = illimité.
	MaxObjectBytes int64
}

type guardedStorage struct {
	inner  StorageProvider
	config storageGuardConfig

	mu          sync.Mutex
	windowStart time.Time
	opsInWindow int
	// refusals compte les refus, pour qu'un seuil trop bas se voie dans les
	// journaux plutôt que de dégrader le service en silence.
	refusals int
}

// ErrStorageQuotaExceeded est rendue quand une garde refuse. À ne pas confondre avec
// ErrObjectNotFound : le handler doit répondre 503 et non 404 — le fichier
// existe, c'est nous qui refusons de le servir.
var ErrStorageQuotaExceeded = fmt.Errorf("storage quota exceeded")

func newGuardedStorage(inner StorageProvider, cfg storageGuardConfig) *guardedStorage {
	if cfg.Window <= 0 {
		cfg.Window = time.Minute
	}
	return &guardedStorage{inner: inner, config: cfg, windowStart: time.Now()}
}

func (g *guardedStorage) Name() string {
	return fmt.Sprintf("%s+garde", g.inner.Name())
}

// allow décompte une opération. Fenêtre glissante grossière — on remet le
// compteur à zéro quand la fenêtre est écoulée, plutôt que de tenir un
// historique : la précision n'apporterait rien à un filet de sécurité.
func (g *guardedStorage) allow() error {
	if g.config.MaxOpsPerWindow <= 0 {
		return nil
	}
	g.mu.Lock()
	defer g.mu.Unlock()

	if time.Since(g.windowStart) >= g.config.Window {
		if g.refusals > 0 {
			logStorageRefusals(g.refusals, g.config.Window)
		}
		g.windowStart = time.Now()
		g.opsInWindow = 0
		g.refusals = 0
	}
	if g.opsInWindow >= g.config.MaxOpsPerWindow {
		g.refusals++
		return ErrStorageQuotaExceeded
	}
	g.opsInWindow++
	return nil
}

func (g *guardedStorage) Open(ctx context.Context, obj StorageObject) (io.ReadSeekCloser, ObjectInfo, error) {
	if err := g.allow(); err != nil {
		return nil, ObjectInfo{}, err
	}
	return g.inner.Open(ctx, obj)
}

func (g *guardedStorage) Put(ctx context.Context, obj StorageObject, data []byte) error {
	// La taille est vérifiée AVANT de consommer une opération : refuser un
	// objet trop gros ne doit pas entamer le budget de la fenêtre.
	if g.config.MaxObjectBytes > 0 && int64(len(data)) > g.config.MaxObjectBytes {
		return fmt.Errorf("%w: objet de %d octets, maximum %d",
			ErrStorageQuotaExceeded, len(data), g.config.MaxObjectBytes)
	}
	if err := g.allow(); err != nil {
		return err
	}
	return g.inner.Put(ctx, obj, data)
}

func (g *guardedStorage) PresignedURL(ctx context.Context, obj StorageObject, ttl time.Duration) (string, error) {
	// Une URL signée ne coûte AUCUNE opération au stockage : elle est calculée
	// localement, sans appel réseau. Elle n'est donc pas décomptée — la borner
	// reviendrait à limiter ce qui ne coûte rien, et pousserait le handler vers
	// le service direct, lui bien plus coûteux.
	return g.inner.PresignedURL(ctx, obj, ttl)
}

// logStorageRefusals signale qu'un seuil a mordu. Sans ce journal, une garde
// trop basse dégraderait le service en silence : des modèles introuvables sans
// que rien n'en explique la cause.
func logStorageRefusals(count int, window time.Duration) {
	log.Printf("⚠️  Garde stockage : %d opération(s) refusée(s) sur la dernière fenêtre de %s — "+
		"relever STORAGE_MAX_OPS_PER_MINUTE si c'est du trafic légitime", count, window)
}

// ─── Configuration ────────────────────────────────────────────────────────

func envInt(name string, fallback int) int {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return fallback
	}
	v, err := strconv.Atoi(raw)
	if err != nil || v < 0 {
		return fallback
	}
	return v
}

func envInt64(name string, fallback int64) int64 {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return fallback
	}
	v, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || v < 0 {
		return fallback
	}
	return v
}

// storageGuardFromEnv lit la configuration des gardes.
//
// Les défauts sont dimensionnés sur l'usage réel : 124 modèles, un catalogue
// stable, une beta interne. Ils laissent une marge large tout en
// arrêtant un emballement — une boucle qui demanderait mille fichiers par
// minute serait coupée.
func storageGuardFromEnv() storageGuardConfig {
	return storageGuardConfig{
		MaxOpsPerWindow: envInt("STORAGE_MAX_OPS_PER_MINUTE", 600),
		Window:          time.Minute,
		MaxObjectBytes:  envInt64("STORAGE_MAX_OBJECT_BYTES", 200<<20), // 200 Mio
	}
}
