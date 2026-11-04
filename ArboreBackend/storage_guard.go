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
// Elle borne les opérations FACTURÉES : les lectures directes comme les URL
// signées, chacune produisant exactement une lecture chez le fournisseur.
//
// L'invariant, et ce qu'il a coûté de ne pas l'avoir (#737) : **une opération
// décomptée = une lecture réellement autorisée.** Une signature qui échoue
// n'autorise rien, donc ne se décompte pas — sinon un fichier servi par un
// support incapable de signer coûterait deux opérations, et le plafond réel
// vaudrait la moitié du plafond configuré.
//
// Elle ne borne pas ce qu'un client fait d'une URL déjà obtenue — mais une URL
// expire en quinze minutes et n'autorise qu'un objet, donc la fenêtre d'abus
// reste étroite.
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
	// generation change à chaque remise à zéro de la fenêtre. Elle sert à
	// n'annuler une réservation que dans la fenêtre qui l'a accordée : sans
	// elle, une annulation arrivant après un basculement de fenêtre
	// décrémenterait le compteur de la fenêtre SUIVANTE, qui n'a rien
	// réservé.
	generation int
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
// allow réserve une opération et rend la génération de fenêtre sur laquelle
// elle a été prise, à repasser à `cancel` si l'opération réservée n'a finalement
// rien autorisé.
func (g *guardedStorage) allow() (int, error) {
	if g.config.MaxOpsPerWindow <= 0 {
		return 0, nil
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
		g.generation++
	}
	if g.opsInWindow >= g.config.MaxOpsPerWindow {
		g.refusals++
		return g.generation, ErrStorageQuotaExceeded
	}
	g.opsInWindow++
	return g.generation, nil
}

// cancel rend une réservation qui n'a rien autorisé.
//
// Le budget borne les opérations FACTURÉES. Une réservation qui n'aboutit à
// aucune lecture chez le fournisseur n'en est pas une, et la garder décomptée
// réduirait le plafond réel sous sa valeur configurée — exactement le défaut
// que #737 a mesuré : `200 op/min` n'en valait que 100.
//
// Rendue seulement si la fenêtre n'a pas basculé entre-temps : sinon on
// retirerait une opération à une fenêtre qui n'en a jamais accordé.
func (g *guardedStorage) cancel(generation int) {
	if g.config.MaxOpsPerWindow <= 0 {
		return
	}
	g.mu.Lock()
	defer g.mu.Unlock()

	if g.generation == generation && g.opsInWindow > 0 {
		g.opsInWindow--
	}
}

func (g *guardedStorage) Open(ctx context.Context, obj StorageObject) (io.ReadSeekCloser, ObjectInfo, error) {
	if _, err := g.allow(); err != nil {
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
	if _, err := g.allow(); err != nil {
		return err
	}
	return g.inner.Put(ctx, obj, data)
}

func (g *guardedStorage) PresignedURL(ctx context.Context, obj StorageObject, ttl time.Duration) (string, error) {
	// DÉCOMPTÉE, contrairement à ce qu'une première version supposait.
	//
	// Générer la signature ne coûte rien : elle est calculée localement, sans
	// appel réseau. Mais elle AUTORISE un téléchargement, et ce téléchargement
	// est une opération facturée par le stockage.
	//
	// Ne pas la décompter rendait la garde inerte en production : avec un
	// support qui sait signer, `serveStorageObject` emprunte cette voie et
	// n'appelle jamais `Open` — le seul chemin qui était compté. La garde
	// n'aurait alors protégé que le cas où elle était inutile.
	//
	// Une signature vaut donc exactement une opération, comme une lecture
	// directe : les deux produisent une lecture facturée.
	//
	// MAIS seulement si elle aboutit (#737). Sur un support qui ne sait pas
	// signer — `filesystem`, celui de la production depuis le 2026-10-21 —
	// l'appel rend `ErrNoPresign`, aucune URL n'est remise, donc RIEN n'est
	// autorisé. `serveStorageObject` retombe alors sur `Open`, qui décompte à
	// son tour : un fichier servi coûtait deux opérations, dont une qui
	// n'autorisait rien.
	//
	// Le plafond réel valait donc la moitié du plafond configuré. Mesuré :
	// `200 op/min` ne laissait passer que 100 vignettes, et le catalogue en
	// compte 123.
	//
	// On réserve d'abord — pour continuer de refuser AVANT d'atteindre le
	// support, comme le vérifie `TestGuardThrottlesPresign` — puis on rend la
	// réservation si rien n'a été signé.
	generation, err := g.allow()
	if err != nil {
		return "", err
	}
	url, err := g.inner.PresignedURL(ctx, obj, ttl)
	if err != nil || url == "" {
		g.cancel(generation)
		return url, err
	}
	return url, nil
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
// Le défaut de 200 opérations par minute vient d'un calcul, pas d'une intuition.
// Soutenu un mois entier, il plafonne à ~8,6 millions d'opérations :
//
//	200 × 60 × 24 × 30 = 8 640 000
//
// soit sous le palier gratuit de 10 millions de lectures mensuelles de
// Cloudflare R2. Le pire cas est donc borné à une facture nulle, ce qui est
// une propriété plus forte que « ça devrait aller ».
//
// La marge reste large : le pic réaliste d'une beta — quelques dizaines
// d'utilisateurs chargeant chacun quelques dizaines de modèles — se compte en
// dizaines d'opérations par minute, pas en centaines.
//
// Sur un MinIO local, où l'opération ne coûte rien, relever franchement : ce
// calcul n'y a aucun sens.
func storageGuardFromEnv() storageGuardConfig {
	return storageGuardConfig{
		MaxOpsPerWindow: envInt("STORAGE_MAX_OPS_PER_MINUTE", 200),
		Window:          time.Minute,
		MaxObjectBytes:  envInt64("STORAGE_MAX_OBJECT_BYTES", 200<<20), // 200 Mio
	}
}
