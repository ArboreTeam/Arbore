package main

// reconcile_guests_mongo_test.go — le chemin nominal du job. (#725 P1)
//
// `reconcile_guests_test.go` tient les gardes « hors base » : refus d'un
// ensemble Firebase vide, période de grâce indésactivable, accord entre les
// collections lues et celles purgées. Il disait aussi ne pas couvrir « le
// chemin nominal, qui exige une base Mongo dont l'environnement de test ne
// dispose pas ».
//
// C'était vrai d'un vrai mongod ; ça ne l'est pas du déploiement simulé de
// `mtest`, qui répond des documents en conserve et enregistre les commandes.
// Pour un job qui SUPPRIME, c'est même le bon niveau : ce qu'on veut prouver
// est quelles collections sont lues, avec quel filtre, et quel uid finit
// effacé. Mesuré avant : `collectMongoUIDs` 0 %, `hasRecentData` 0 %,
// `reconcileGuests` 10,7 %.
//
// Les deux fonctions parcourent `uidBearingCollections`, qui est une MAP :
// l'ordre des collections est indéterminé d'une exécution à l'autre. Les
// assertions ci-dessous ne s'appuient donc jamais sur cet ordre, et les
// réponses simulées sont interchangeables.

import (
	"bytes"
	"context"
	"log"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo/integration/mtest"
)

// repondreDistinct pose une réponse `distinct` par collection portant un uid.
func repondreDistinct(mt *mtest.T, valeurs ...interface{}) {
	liste := bson.A(valeurs)
	for range uidBearingCollections {
		mt.AddMockResponses(mtest.CreateSuccessResponse(bson.E{Key: "values", Value: liste}))
	}
}

// repondreCount pose `combien` réponses de comptage, toutes à `n`.
func repondreCount(mt *mtest.T, combien int, n int32) {
	for i := 0; i < combien; i++ {
		mt.AddMockResponses(mtest.CreateSuccessResponse(
			bson.E{Key: "cursor", Value: bson.D{
				{Key: "id", Value: int64(0)},
				{Key: "ns", Value: "arbore.c"},
				{Key: "firstBatch", Value: bson.A{bson.D{{Key: "n", Value: n}}}},
			}},
		))
	}
}

// --- collectMongoUIDs ----------------------------------------------------

// TestCollectMongoUIDsInterrogeToutesLesCollectionsPortantUnUid : une
// collection oubliée, et ses uid ne seraient jamais candidats à l'orphelinat —
// des données personnelles sans propriétaire qui survivraient indéfiniment.
func TestCollectMongoUIDsInterrogeToutesLesCollectionsPortantUnUid(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("une requête distinct par collection", func(mt *mtest.T) {
		repondreDistinct(mt, "uid-a")

		uids, err := collectMongoUIDs(context.Background(), mt.DB)
		require.NoError(t, err)
		require.Equal(t, map[string]struct{}{"uid-a": {}}, uids)

		interrogees := map[string]string{}
		for _, event := range mt.GetAllStartedEvents() {
			require.Equal(t, "distinct", event.CommandName)
			collection := event.Command.Lookup("distinct").StringValue()
			interrogees[collection] = event.Command.Lookup("key").StringValue()
		}
		require.Equal(t, uidBearingCollections, interrogees,
			"chaque collection doit être lue sur SON champ d'uid")
	})
}

// TestCollectMongoUIDsUnitLesCollectionsEtIgnoreLesValeursInexploitables.
//
// Une chaîne vide n'est pas un uid : la retenir ferait passer le document pour
// orphelin et déclencherait une purge filtrée sur `""`.
func TestCollectMongoUIDsUnitLesCollectionsEtIgnoreLesValeursInexploitables(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("union, sans vide ni non-chaîne", func(mt *mtest.T) {
		repondreDistinct(mt, "uid-a", "uid-b", "", int32(42), nil, "uid-a")

		uids, err := collectMongoUIDs(context.Background(), mt.DB)
		require.NoError(t, err)
		require.Equal(t, map[string]struct{}{"uid-a": {}, "uid-b": {}}, uids)
	})
}

// TestCollectMongoUIDsEchoueSiUneCollectionEstIllisible : fail-closed. Une
// lecture partielle rendrait un ensemble Mongo incomplet, donc des uid absents
// de la liste — sans conséquence ici — mais surtout elle signale une base en
// mauvais état, sur laquelle il ne faut pas supprimer.
func TestCollectMongoUIDsEchoueSiUneCollectionEstIllisible(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("erreur propagée", func(mt *mtest.T) {
		mt.AddMockResponses(mtest.CreateCommandErrorResponse(mtest.CommandError{
			Code: 13, Message: "not authorized", Name: "Unauthorized",
		}))

		uids, err := collectMongoUIDs(context.Background(), mt.DB)
		require.Error(t, err)
		require.Nil(t, uids)
	})
}

// --- hasRecentData -------------------------------------------------------

// TestHasRecentDataTraiteUnIdNonObjectIdCommeRECENT est la garde la plus
// subtile du job, et elle ne se voit que dans le filtre.
//
// L'âge est lu dans l'horodatage embarqué de l'ObjectId. Un document dont le
// `_id` n'en est pas un a un âge INDÉTERMINABLE — et l'indétermination doit
// protéger la donnée, pas l'exposer. Sans la branche
// `{_id: {$not: {$type: "objectId"}}}`, un tel document serait tenu pour vieux
// et purgé.
func TestHasRecentDataTraiteUnIdNonObjectIdCommeRECENT(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("la branche $not $type objectId est présente", func(mt *mtest.T) {
		repondreCount(mt, len(uidBearingCollections), 0)

		_, err := hasRecentData(context.Background(), mt.DB, "uid-x", time.Now())
		require.NoError(t, err)

		events := mt.GetAllStartedEvents()
		require.NotEmpty(t, events)
		for _, event := range events {
			require.Equal(t, "aggregate", event.CommandName)
			branches := filtreDuComptage(t, event.Command).Lookup("$or")
			valeurs, err := branches.Array().Values()
			require.NoError(t, err)
			require.Len(t, valeurs, 2, "deux branches : récent, ou âge indéterminable")

			var vuGte, vuNonObjectID bool
			for _, valeur := range valeurs {
				critere := valeur.Document().Lookup("_id").Document()
				if _, err := critere.LookupErr("$gte"); err == nil {
					vuGte = true
				}
				if negation, err := critere.LookupErr("$not"); err == nil {
					require.Equal(t, "objectId",
						negation.Document().Lookup("$type").StringValue())
					vuNonObjectID = true
				}
			}
			require.True(t, vuGte, "il manque la branche « plus récent que le seuil »")
			require.True(t, vuNonObjectID, "il manque la branche « âge indéterminable »")
		}
	})
}

// filtreDuComptage extrait le filtre du `$match` que `CountDocuments` envoie :
// le pilote le traduit en pipeline d'agrégation, pas en `count`.
func filtreDuComptage(t *testing.T, commande bson.Raw) bson.Raw {
	t.Helper()
	etapes, err := commande.Lookup("pipeline").Array().Values()
	require.NoError(t, err)
	require.NotEmpty(t, etapes)
	return etapes[0].Document().Lookup("$match").Document()
}

// TestHasRecentDataSArreteDesQuUneCollectionPorteUneDonneeRecente : un seul
// document récent suffit à épargner l'uid, et il est inutile d'interroger les
// autres collections.
func TestHasRecentDataSArreteDesQuUneCollectionPorteUneDonneeRecente(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("court-circuit", func(mt *mtest.T) {
		repondreCount(mt, 1, 1)

		recent, err := hasRecentData(context.Background(), mt.DB, "uid-recent", time.Now())
		require.NoError(t, err)
		require.True(t, recent)
		require.Len(t, mt.GetAllStartedEvents(), 1,
			"la première collection qui répond suffit")
	})
}

// TestHasRecentDataRendFauxQuandAucuneCollectionNEstRecente : le cas qui
// AUTORISE la suppression. Il doit exiger que les quatre collections aient
// répondu zéro.
func TestHasRecentDataRendFauxQuandAucuneCollectionNEstRecente(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("quatre zéros", func(mt *mtest.T) {
		repondreCount(mt, len(uidBearingCollections), 0)

		recent, err := hasRecentData(context.Background(), mt.DB, "uid-vieux", time.Now())
		require.NoError(t, err)
		require.False(t, recent)
		require.Len(t, mt.GetAllStartedEvents(), len(uidBearingCollections),
			"toutes les collections doivent avoir été consultées avant d'autoriser la purge")
	})
}

// TestHasRecentDataEchoueFermeSurErreur : une erreur de comptage ne doit
// JAMAIS rendre « pas récent ». Un `false, err` mal interprété par l'appelant
// purgerait un compte dont on ne sait rien.
func TestHasRecentDataEchoueFermeSurErreur(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("erreur remontée", func(mt *mtest.T) {
		mt.AddMockResponses(mtest.CreateCommandErrorResponse(mtest.CommandError{
			Code: 11600, Message: "interrupted at shutdown", Name: "InterruptedAtShutdown",
		}))

		recent, err := hasRecentData(context.Background(), mt.DB, "uid-x", time.Now())
		require.Error(t, err)
		require.False(t, recent)
	})
}

// --- reconcileGuests, chemin nominal -------------------------------------

const (
	uidVivant   = "uid-vivant-cote-firebase"
	uidOrphelin = "uid-absent-de-firebase"
)

func firebaseAvecLeVivant() map[string]struct{} {
	return map[string]struct{}{uidVivant: {}}
}

// TestReconcileNePurgeQueLUidAbsentDeFirebase est le test central du job.
//
// Il ne vérifie pas seulement que l'orphelin est retenu : il vérifie que
// CHAQUE suppression envoyée porte l'uid de l'orphelin et jamais celui du
// compte vivant. C'est la seule assertion qui dise « le job n'a pas supprimé
// le mauvais compte ».
func TestReconcileNePurgeQueLUidAbsentDeFirebase(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("un vivant, un orphelin", func(mt *mtest.T) {
		repondreDistinct(mt, uidVivant, uidOrphelin)
		repondreCount(mt, len(uidBearingCollections), 0) // rien de récent
		mockPurgeOK(mt, 2, 1, 0, 1)

		report, err := reconcileGuests(context.Background(), mt.DB,
			firebaseAvecLeVivant(), reconcileOptions{})
		require.NoError(t, err)

		require.Equal(t, []string{uidOrphelin}, report.Orphans)
		require.Empty(t, report.SkippedGrace)
		require.Equal(t, 1, report.FirebaseUIDs)
		require.Equal(t, 2, report.MongoUIDs)
		require.Equal(t,
			purgeCounts{Gardens: 2, Consents: 1, LegacyPosts: 0, Users: 1},
			report.Purged)

		var suppressions int
		for _, event := range mt.GetAllStartedEvents() {
			if event.CommandName != "delete" {
				continue
			}
			suppressions++
			valeurs, err := event.Command.Lookup("deletes").Array().Values()
			require.NoError(t, err)
			filtre := valeurs[0].Document()
			require.NotContains(t, filtre.String(), uidVivant,
				"un compte présent côté Firebase ne doit jamais être visé")
			require.Contains(t, filtre.String(), uidOrphelin)
		}
		require.Equal(t, 4, suppressions)
	})
}

// TestReconcileEpargneUnOrphelinDansLaPeriodeDeGrace : l'uid est bien absent
// de Firebase, mais il porte une donnée trop récente. Le temps qu'une création
// se propage jusqu'au snapshot Firebase, on ne touche à rien.
func TestReconcileEpargneUnOrphelinDansLaPeriodeDeGrace(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("épargné, et rien de supprimé", func(mt *mtest.T) {
		repondreDistinct(mt, uidVivant, uidOrphelin)
		repondreCount(mt, 1, 1) // une donnée récente : court-circuit

		report, err := reconcileGuests(context.Background(), mt.DB,
			firebaseAvecLeVivant(), reconcileOptions{})
		require.NoError(t, err)

		require.Equal(t, []string{uidOrphelin}, report.SkippedGrace)
		require.Empty(t, report.Orphans)
		require.Equal(t, purgeCounts{}, report.Purged)

		for _, event := range mt.GetAllStartedEvents() {
			require.NotEqual(t, "delete", event.CommandName,
				"aucune suppression pendant la période de grâce")
		}
	})
}

// TestReconcileEnSimulationNeSupprimeRien : la garde 4 de #393. Le mode par
// défaut retient les orphelins et n'envoie AUCUNE suppression — le drapeau
// `-apply` est ce qui arme le job.
func TestReconcileEnSimulationNeSupprimeRien(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("dry-run", func(mt *mtest.T) {
		repondreDistinct(mt, uidVivant, uidOrphelin)
		repondreCount(mt, len(uidBearingCollections), 0)

		report, err := reconcileGuests(context.Background(), mt.DB,
			firebaseAvecLeVivant(), reconcileOptions{DryRun: true})
		require.NoError(t, err)

		require.True(t, report.DryRun)
		require.Equal(t, []string{uidOrphelin}, report.Orphans,
			"la simulation doit quand même DIRE ce qu'elle supprimerait")
		require.Equal(t, purgeCounts{}, report.Purged)

		for _, event := range mt.GetAllStartedEvents() {
			require.NotEqual(t, "delete", event.CommandName,
				"une simulation qui supprime n'est pas une simulation")
		}
	})
}

// TestReconcileAppliqueLaPeriodeDeGraceParDefautAuSeuil : `Grace` à zéro ne
// désactive pas la garde — `resolveGrace` retombe sur sept jours. Le test le
// prouve là où ça compte, dans le SEUIL effectivement envoyé à Mongo, et non
// seulement dans la fonction qui le calcule.
func TestReconcileAppliqueLaPeriodeDeGraceParDefautAuSeuil(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("seuil à sept jours", func(mt *mtest.T) {
		repondreDistinct(mt, uidOrphelin)
		repondreCount(mt, 1, 1)

		avant := time.Now()
		_, err := reconcileGuests(context.Background(), mt.DB,
			firebaseAvecLeVivant(), reconcileOptions{Grace: 0})
		require.NoError(t, err)

		var vu bool
		for _, event := range mt.GetAllStartedEvents() {
			if event.CommandName != "aggregate" {
				continue
			}
			vu = true
			branches, err := filtreDuComptage(t, event.Command).Lookup("$or").Array().Values()
			require.NoError(t, err)
			for _, branche := range branches {
				critere := branche.Document().Lookup("_id").Document()
				seuil, err := critere.LookupErr("$gte")
				if err != nil {
					continue
				}
				// L'horodatage de l'ObjectId est à la seconde près ; une marge
				// d'une minute absorbe l'arrondi et la durée du test.
				age := avant.Sub(seuil.ObjectID().Timestamp())
				require.InDelta(t, defaultReconcileGrace.Seconds(), age.Seconds(), 60,
					"un Grace nul doit retomber sur les sept jours par défaut")
			}
		}
		require.True(t, vu, "aucun comptage observé")
	})
}

// TestLogReconcileReportNeJournaliseAucunUid : un uid est une donnée
// personnelle, et le journal a sa propre durée de conservation (#385). Un job
// qui supprime des données personnelles ne doit pas en recopier l'identifiant
// dans des traces qui, elles, survivent.
func TestLogReconcileReportNeJournaliseAucunUid(t *testing.T) {
	var capture bytes.Buffer
	sortiePrecedente := log.Writer()
	drapeauxPrecedents := log.Flags()
	log.SetOutput(&capture)
	log.SetFlags(0)
	t.Cleanup(func() {
		log.SetOutput(sortiePrecedente)
		log.SetFlags(drapeauxPrecedents)
	})

	logReconcileReport(reconcileReport{
		FirebaseUIDs: 2,
		MongoUIDs:    3,
		Orphans:      []string{uidOrphelin},
		SkippedGrace: []string{uidVivant},
		Purged:       purgeCounts{Gardens: 1, Consents: 1, LegacyPosts: 0, Users: 1},
	})

	journal := capture.String()
	require.NotContains(t, journal, uidOrphelin, "un uid ne doit jamais atterrir dans le journal")
	require.NotContains(t, journal, uidVivant)
	require.Contains(t, journal, "orphelins retenus       : 1", "les totaux, eux, sont attendus")
	require.Contains(t, journal, "SUPPRESSION RÉELLE",
		"le mode doit être explicite : on doit pouvoir relire si le job a supprimé")
}

// TestLogReconcileReportDitQuUneSimulationNaRienSupprime : relire un journal
// sans savoir si le job était armé serait inexploitable après coup.
func TestLogReconcileReportDitQuUneSimulationNaRienSupprime(t *testing.T) {
	var capture bytes.Buffer
	sortiePrecedente := log.Writer()
	log.SetOutput(&capture)
	t.Cleanup(func() { log.SetOutput(sortiePrecedente) })

	logReconcileReport(reconcileReport{DryRun: true, Orphans: []string{uidOrphelin}})

	journal := capture.String()
	require.Contains(t, journal, "SIMULATION (aucune suppression)")
	require.NotContains(t, journal, "supprimés —",
		"une simulation ne doit pas afficher de ligne de suppression")
}
