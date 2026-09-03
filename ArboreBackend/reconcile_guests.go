// reconcile_guests.go — réconciliation Firebase ↔ Mongo (#393).
//
// Le nettoyage automatique des comptes anonymes inactifs a été activé le
// 2026-09-02 : Firebase supprime un compte invité après 30 jours d'inactivité.
// Les documents Mongo indexés par cet uid deviendraient alors des données
// personnelles orphelines — plus de propriétaire identifiable, personne pour en
// demander l'effacement, aucune durée de conservation. Ce job les supprime.
//
// C'est un effaceur de production piloté par un système externe. Quatre gardes
// le rendent acceptable, et aucune n'est optionnelle :
//
//  1. Fail-closed. On ne supprime que sur une absence CONFIRMÉE. Toute erreur
//     Firebase interrompt le job sans rien toucher.
//  2. Énumération complète et paginée (middleware.ListAllUIDs), jamais un
//     GetUser par uid : un échec isolé ne peut pas passer pour une absence.
//  3. Période de grâce. Un uid ayant une donnée récente est épargné, le temps
//     qu'une création se propage jusqu'au snapshot Firebase.
//  4. Simulation par défaut. La suppression réelle exige un drapeau explicite.

package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"ArboreBackend/middleware"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

// defaultReconcileGrace est le délai en deçà duquel une donnée n'est jamais
// supprimée, quel que soit l'état Firebase.
const defaultReconcileGrace = 7 * 24 * time.Hour

// uidBearingCollections liste les collections portant un uid, avec le nom du
// champ qui le porte. `community_posts` utilise `userId` — hérité des anciennes
// builds TestFlight, cf. deleteLegacyCommunityData.
//
// Toute collection ajoutée ici doit l'être aussi dans purgeUserData, et
// réciproquement : la première décide qui est orphelin, la seconde ce qu'on
// efface. Le test TestReconcileCollectionsMatchPurge verrouille cet accord.
var uidBearingCollections = map[string]string{
	"users":           "uid",
	"gardens":         "uid",
	"consents":        "uid",
	"community_posts": "userId",
}

// resolveGrace applique la période de grâce par défaut. Une valeur nulle ou
// négative ne désactive PAS la garde : elle retombe sur les 7 jours. Permettre
// « zéro jour de grâce » par simple omission serait une arme chargée.
func resolveGrace(requested time.Duration) time.Duration {
	if requested <= 0 {
		return defaultReconcileGrace
	}
	return requested
}

type reconcileOptions struct {
	DryRun bool
	Grace  time.Duration
}

type reconcileReport struct {
	FirebaseUIDs int
	MongoUIDs    int
	Orphans      []string
	SkippedGrace []string
	Purged       purgeCounts
	DryRun       bool
}

// collectMongoUIDs rassemble les uid distincts référencés dans Mongo.
func collectMongoUIDs(ctx context.Context, db *mongo.Database) (map[string]struct{}, error) {
	uids := make(map[string]struct{})
	for collection, field := range uidBearingCollections {
		values, err := db.Collection(collection).Distinct(ctx, field, bson.M{})
		if err != nil {
			return nil, fmt.Errorf("lecture des uid de %s: %w", collection, err)
		}
		for _, value := range values {
			if uid, ok := value.(string); ok && uid != "" {
				uids[uid] = struct{}{}
			}
		}
	}
	return uids, nil
}

// hasRecentData dit si un uid porte une donnée trop récente pour être purgée.
//
// L'âge est lu dans l'horodatage embarqué de l'ObjectId plutôt que dans un
// champ `createdAt` : celui de `gardens` est une date BSON, celui de `users`
// une chaîne. Une comparaison uniforme sur `_id` évite d'avoir à traiter chaque
// collection différemment, et couvre celles qui n'ont aucun champ de date.
//
// Un document dont le `_id` n'est PAS un ObjectId est considéré comme récent :
// son âge est indéterminable, et l'indétermination doit protéger la donnée.
func hasRecentData(ctx context.Context, db *mongo.Database, uid string, cutoff time.Time) (bool, error) {
	threshold := primitive.NewObjectIDFromTimestamp(cutoff)
	for collection, field := range uidBearingCollections {
		filter := bson.M{
			field: uid,
			"$or": []bson.M{
				{"_id": bson.M{"$gte": threshold}},
				{"_id": bson.M{"$not": bson.M{"$type": "objectId"}}},
			},
		}
		count, err := db.Collection(collection).CountDocuments(ctx, filter, nil)
		if err != nil {
			return false, fmt.Errorf("vérification d'âge sur %s: %w", collection, err)
		}
		if count > 0 {
			return true, nil
		}
	}
	return false, nil
}

// reconcileGuests supprime les données Mongo dont l'uid n'existe plus côté
// Firebase.
//
// `firebaseUIDs` est passé en paramètre plutôt que récupéré ici : la logique
// reste testable sans Firebase, et l'appelant porte la responsabilité d'avoir
// obtenu un ensemble COMPLET — un ensemble incomplet provoquerait des
// suppressions massives.
func reconcileGuests(
	ctx context.Context,
	db *mongo.Database,
	firebaseUIDs map[string]struct{},
	options reconcileOptions,
) (reconcileReport, error) {
	report := reconcileReport{DryRun: options.DryRun, FirebaseUIDs: len(firebaseUIDs)}

	// Garde supplémentaire, non listée dans #393 mais décisive : un ensemble
	// Firebase vide ferait passer TOUS les uid Mongo pour orphelins. Aucun
	// projet en service n'a zéro compte ; c'est le signe d'une énumération
	// partielle ou d'un mauvais service account, pas d'une base vide.
	if len(firebaseUIDs) == 0 {
		return report, fmt.Errorf("énumération Firebase vide : refus de considérer tous les uid Mongo comme orphelins")
	}

	cutoff := time.Now().Add(-resolveGrace(options.Grace))

	mongoUIDs, err := collectMongoUIDs(ctx, db)
	if err != nil {
		return report, err
	}
	report.MongoUIDs = len(mongoUIDs)

	for uid := range mongoUIDs {
		if _, exists := firebaseUIDs[uid]; exists {
			continue
		}

		recent, err := hasRecentData(ctx, db, uid, cutoff)
		if err != nil {
			return report, err
		}
		if recent {
			report.SkippedGrace = append(report.SkippedGrace, uid)
			continue
		}

		report.Orphans = append(report.Orphans, uid)
		if options.DryRun {
			continue
		}

		counts, err := purgeUserData(ctx, db, uid)
		report.Purged.Gardens += counts.Gardens
		report.Purged.Consents += counts.Consents
		report.Purged.LegacyPosts += counts.LegacyPosts
		report.Purged.Users += counts.Users
		if err != nil {
			return report, fmt.Errorf("purge de l'uid orphelin: %w", err)
		}
	}

	return report, nil
}

// logReconcileReport journalise les totaux, jamais les uid eux-mêmes : un uid
// est une donnée personnelle, et le journal a sa propre durée de conservation
// (#385).
func logReconcileReport(report reconcileReport) {
	mode := "SUPPRESSION RÉELLE"
	if report.DryRun {
		mode = "SIMULATION (aucune suppression)"
	}
	log.Printf("🔄 Réconciliation Firebase ↔ Mongo — %s", mode)
	log.Printf("   comptes Firebase        : %d", report.FirebaseUIDs)
	log.Printf("   uid référencés en Mongo : %d", report.MongoUIDs)
	log.Printf("   orphelins retenus       : %d", len(report.Orphans))
	log.Printf("   épargnés (période grâce): %d", len(report.SkippedGrace))
	if !report.DryRun {
		log.Printf("   supprimés — gardens: %d, consents: %d, legacyPosts: %d, users: %d",
			report.Purged.Gardens, report.Purged.Consents,
			report.Purged.LegacyPosts, report.Purged.Users)
	}
}

// reconcileTimeout borne la durée totale du job. Généreux : l'énumération
// Firebase et le balayage Mongo croissent avec la base, et une interruption au
// milieu est sans danger — les suppressions sont idempotentes, le passage
// suivant reprend le reliquat.
const reconcileTimeout = 30 * time.Minute

// runReconcileGuests exécute le job puis rend un code de sortie exploitable par
// le cron : toute erreur est remontée, y compris une énumération Firebase
// incomplète — auquel cas rien n'a été supprimé.
func runReconcileGuests(apply bool) error {
	ctx, cancel := context.WithTimeout(context.Background(), reconcileTimeout)
	defer cancel()

	firebaseUIDs, err := middleware.ListAllUIDs(ctx)
	if err != nil {
		return fmt.Errorf("énumération Firebase: %w", err)
	}

	report, err := reconcileGuests(ctx, client.Database(prodDBName), firebaseUIDs, reconcileOptions{
		DryRun: !apply,
	})
	logReconcileReport(report)
	if err != nil {
		return err
	}
	if report.DryRun && len(report.Orphans) > 0 {
		log.Printf("ℹ️  Relancer avec -apply pour supprimer ces %d uid orphelins.", len(report.Orphans))
	}
	return nil
}
