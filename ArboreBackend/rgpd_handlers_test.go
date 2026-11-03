package main

// rgpd_handlers_test.go — les deux routes que le RGPD impose. (#725 P1)
//
// `exportUserData` (Art. 15 et 20, droit d'accès et portabilité) et
// `deleteUser` (Art. 17, droit à l'effacement) étaient à **0 %** de
// couverture. #338 porte par ailleurs une faille Art. 17 confirmée, et le
// seul filet côté iOS — `RGPDEndpointsIntegrationTests` — se neutralise par
// `XCTSkip` quand le backend est injoignable : il passe en vert sans rien
// exécuter. Ces routes n'étaient donc éprouvées nulle part.
//
// Les handlers lisent la base par `getDatabaseForRequest`, qui retombe sur la
// variable de paquet `client`. Les tests la remplacent par le client simulé de
// `mtest` et la restaurent ensuite ; ils ne peuvent donc pas tourner en
// parallèle, et ne le demandent pas.

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/integration/mtest"
)

// brancherClientSimule substitue le client simulé à celui du paquet, et rend
// la fonction de restauration.
func brancherClientSimule(t *testing.T, simule *mongo.Client) {
	t.Helper()
	precedent := client
	client = simule
	t.Cleanup(func() { client = precedent })
}

// appelerHandler monte le handler derrière un routeur minimal, avec ou sans
// uid authentifié — c'est le middleware Firebase qui le pose en production.
func appelerHandler(handler gin.HandlerFunc, uid string, methode, chemin string) *httptest.ResponseRecorder {
	gin.SetMode(gin.TestMode)
	routeur := gin.New()
	routeur.Handle(methode, chemin, func(c *gin.Context) {
		if uid != "" {
			c.Set("uid", uid)
		}
		handler(c)
	})
	enregistreur := httptest.NewRecorder()
	routeur.ServeHTTP(enregistreur, httptest.NewRequest(methode, chemin, nil))
	return enregistreur
}

// --- deleteUser ----------------------------------------------------------

// TestDeleteUserSansUidNeToucheJamaisALaBase : un 401 est attendu, mais ce
// n'est pas le point. Le point est qu'AUCUNE commande ne parte vers Mongo —
// une suppression déclenchée avant le contrôle d'identité effacerait les
// données de quelqu'un d'autre.
func TestDeleteUserSansUidNeToucheJamaisALaBase(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("401 et zéro commande", func(mt *mtest.T) {
		brancherClientSimule(t, mt.Client)

		reponse := appelerHandler(deleteUser, "", http.MethodDelete, "/users/me")

		require.Equal(t, http.StatusUnauthorized, reponse.Code)
		require.Empty(t, mt.GetAllStartedEvents(),
			"aucune commande Mongo avant l'authentification")
	})
}

// TestDeleteUserPurgeLesQuatreCollectionsEtRendLesComptes couvre le chemin
// nominal complet du droit à l'effacement.
//
// `DeleteFirebaseUser` rend nil hors mode release quand le SDK n'est pas
// initialisé : la suppression de l'identité Firebase n'est donc pas exercée
// ici, elle l'est par le test de mode release ci-dessous.
func TestDeleteUserPurgeLesQuatreCollectionsEtRendLesComptes(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("200 et comptes exacts", func(mt *mtest.T) {
		brancherClientSimule(t, mt.Client)

		// 1. lecture du token Apple (aucun document), puis la purge.
		mt.AddMockResponses(mtest.CreateCursorResponse(0, "arbore.users", mtest.FirstBatch))
		mockPurgeOK(mt, 3, 2, 1, 1)

		reponse := appelerHandler(deleteUser, "uid-a-supprimer", http.MethodDelete, "/users/me")
		require.Equal(t, http.StatusOK, reponse.Code)

		var corps map[string]any
		require.NoError(t, json.Unmarshal(reponse.Body.Bytes(), &corps))
		require.EqualValues(t, 3, corps["gardensDeleted"])
		require.EqualValues(t, 2, corps["consentsDeleted"])
		require.EqualValues(t, 1, corps["legacyPostsDeleted"])
		require.Equal(t, true, corps["authenticationDeleted"])

		require.Equal(t, [][2]string{
			{"find", "users"},
			{"delete", "gardens"},
			{"delete", "consents"},
			{"find", "community_posts"},
			{"delete", "community_posts"},
			{"delete", "users"},
		}, commandesEnvoyees(mt))
	})
}

// TestDeleteUserCibleUnDocumentPORTANTUnTokenApple verrouille le constat 1 de
// l'audit #338 vu depuis la révocation.
//
// Avec un `FindOne` sur le seul `uid`, un compte à plusieurs documents pouvait
// rendre une copie sans token et sauter la révocation Apple en silence —
// constaté en production sur 2 des 7 comptes dupliqués. Le filtre doit donc
// exiger la PRÉSENCE du token.
func TestDeleteUserCibleUnDocumentPORTANTUnTokenApple(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("le filtre exige le token", func(mt *mtest.T) {
		brancherClientSimule(t, mt.Client)

		mt.AddMockResponses(mtest.CreateCursorResponse(0, "arbore.users", mtest.FirstBatch))
		mockPurgeOK(mt, 0, 0, 0, 1)

		appelerHandler(deleteUser, "uid-apple", http.MethodDelete, "/users/me")

		var vu bool
		for _, event := range mt.GetAllStartedEvents() {
			if event.CommandName != "find" ||
				event.Command.Lookup("find").StringValue() != "users" {
				continue
			}
			vu = true
			filtre := event.Command.Lookup("filter").Document()
			require.Equal(t, "uid-apple", filtre.Lookup("uid").StringValue())
			critere := filtre.Lookup("appleRefreshTokenEncrypted").Document()
			require.True(t, critere.Lookup("$exists").Boolean(),
				"le document lu doit PORTER un token, pas seulement l'uid")
		}
		require.True(t, vu, "la lecture du token Apple n'a pas eu lieu")
	})
}

// TestDeleteUserNommeLaCollectionEnEchec : le message par collection fait
// partie du contrat de l'API, et c'est `purgeStepError` qui le permet. Sans
// lui, toute panne rendait « Erreur lors de la suppression de l'utilisateur »,
// y compris quand c'est `gardens` qui a échoué.
func TestDeleteUserNommeLaCollectionEnEchec(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("500 avec le message de gardens", func(mt *mtest.T) {
		brancherClientSimule(t, mt.Client)

		mt.AddMockResponses(
			mtest.CreateCursorResponse(0, "arbore.users", mtest.FirstBatch),
			mtest.CreateCommandErrorResponse(mtest.CommandError{
				Code: 11600, Message: "interrupted at shutdown", Name: "InterruptedAtShutdown",
			}),
		)

		reponse := appelerHandler(deleteUser, "uid-echec", http.MethodDelete, "/users/me")

		require.Equal(t, http.StatusInternalServerError, reponse.Code)
		require.Contains(t, reponse.Body.String(), "suppression des gardens")

		for _, event := range mt.GetAllStartedEvents() {
			if event.CommandName != "delete" {
				continue
			}
			require.NotEqual(t, "users", event.Command.Lookup("delete").StringValue(),
				"le document utilisateur doit survivre pour qu'un rejeu retrouve l'uid")
		}
	})
}

// TestDeleteUserRend503SiFirebaseEstIndisponible : en mode release, un SDK
// Firebase absent est une panne, pas un succès silencieux. Mongo est DÉJÀ
// purgée à ce stade — le code `AUTH_DELETE_FAILED` dit au client de rejouer,
// et les suppressions sont idempotentes.
func TestDeleteUserRend503SiFirebaseEstIndisponible(t *testing.T) {
	t.Setenv("GIN_MODE", "release")

	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("503 AUTH_DELETE_FAILED", func(mt *mtest.T) {
		brancherClientSimule(t, mt.Client)

		mt.AddMockResponses(mtest.CreateCursorResponse(0, "arbore.users", mtest.FirstBatch))
		mockPurgeOK(mt, 1, 1, 0, 1)

		reponse := appelerHandler(deleteUser, "uid-firebase-ko", http.MethodDelete, "/users/me")

		require.Equal(t, http.StatusServiceUnavailable, reponse.Code)
		require.Contains(t, reponse.Body.String(), "AUTH_DELETE_FAILED")

		require.Equal(t, [][2]string{
			{"find", "users"},
			{"delete", "gardens"},
			{"delete", "consents"},
			{"find", "community_posts"},
			{"delete", "community_posts"},
			{"delete", "users"},
		}, commandesEnvoyees(mt),
			"la purge Mongo doit avoir eu lieu avant l'échec Firebase")
	})
}

// --- exportUserData ------------------------------------------------------

// TestExportUserDataSansUidNeLitRien : symétrique du test de suppression. Un
// export est une divulgation ; il ne doit pas commencer avant l'identification.
func TestExportUserDataSansUidNeLitRien(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("401 et zéro commande", func(mt *mtest.T) {
		brancherClientSimule(t, mt.Client)

		reponse := appelerHandler(exportUserData, "", http.MethodGet, "/users/me/export")

		require.Equal(t, http.StatusUnauthorized, reponse.Code)
		require.Empty(t, mt.GetAllStartedEvents())
	})
}

// TestExportUserDataSansProfilExporteQuandMemeLeReste est le cas que le
// commentaire du handler appelle à protéger, et le seul qui soit subtil.
//
// Une session invité (#391) ne crée aucun document `users`, mais peut détenir
// des jardins et des consentements. Répondre 404 priverait son titulaire de
// son droit d'accès (Art. 15) sur des données qui existent bel et bien.
func TestExportUserDataSansProfilExporteQuandMemeLeReste(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("200, hasProfile false, jardins présents", func(mt *mtest.T) {
		brancherClientSimule(t, mt.Client)

		mt.AddMockResponses(
			// users : aucun document, comme pour un invité.
			mtest.CreateCursorResponse(0, "arbore.users", mtest.FirstBatch),
			mtest.CreateCursorResponse(0, "arbore.gardens", mtest.FirstBatch,
				bson.D{{Key: "uid", Value: "uid-invite"}, {Key: "name", Value: "Balcon"}}),
			mtest.CreateCursorResponse(0, "arbore.consents", mtest.FirstBatch,
				bson.D{{Key: "uid", Value: "uid-invite"}}),
		)

		reponse := appelerHandler(exportUserData, "uid-invite", http.MethodGet, "/users/me/export")
		require.Equal(t, http.StatusOK, reponse.Code)

		var corps struct {
			Metadata struct {
				HasProfile    bool `json:"hasProfile"`
				TotalGardens  int  `json:"totalGardens"`
				TotalConsents int  `json:"totalConsents"`
			} `json:"metadata"`
			User struct {
				UID string `json:"uid"`
			} `json:"user"`
		}
		require.NoError(t, json.Unmarshal(reponse.Body.Bytes(), &corps))

		require.False(t, corps.Metadata.HasProfile,
			"l'absence de profil doit être DITE, pas masquée")
		require.Equal(t, 1, corps.Metadata.TotalGardens,
			"un invité sans profil garde son droit d'accès sur ses jardins")
		require.Equal(t, 1, corps.Metadata.TotalConsents)
		require.Equal(t, "uid-invite", corps.User.UID)
	})
}

// TestExportUserDataNeDivulgueJamaisLeTokenApple : l'export est une
// divulgation volontaire de données personnelles. Le refresh token Apple est
// un SECRET D'AUTHENTIFICATION, pas une donnée personnelle à porter ailleurs —
// l'inclure donnerait à quiconque obtient l'export le pouvoir d'agir sur le
// compte Apple.
//
// Le handler construit une réponse champ par champ, donc l'omission est
// explicite. Ce test la verrouille : ajouter un `user` sérialisé en entier le
// ferait échouer.
func TestExportUserDataNeDivulgueJamaisLeTokenApple(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("le secret reste hors de l'export", func(mt *mtest.T) {
		brancherClientSimule(t, mt.Client)

		const secret = "SECRET-APPLE-A-NE-JAMAIS-EXPORTER"
		mt.AddMockResponses(
			mtest.CreateCursorResponse(0, "arbore.users", mtest.FirstBatch, bson.D{
				{Key: "uid", Value: "uid-apple"},
				{Key: "email", Value: "personne@example.test"},
				{Key: "appleRefreshTokenEncrypted", Value: []byte(secret)},
			}),
			mtest.CreateCursorResponse(0, "arbore.gardens", mtest.FirstBatch),
			mtest.CreateCursorResponse(0, "arbore.consents", mtest.FirstBatch),
		)

		reponse := appelerHandler(exportUserData, "uid-apple", http.MethodGet, "/users/me/export")
		require.Equal(t, http.StatusOK, reponse.Code)

		corps := reponse.Body.String()
		require.Contains(t, corps, "personne@example.test",
			"l'export doit bien contenir les données personnelles")
		require.NotContains(t, corps, secret,
			"le refresh token Apple ne doit jamais sortir dans l'export")
		require.NotContains(t, strings.ToLower(corps), "applerefreshtoken",
			"ni la valeur, ni le champ")
	})
}

// TestExportUserDataRemonteUneErreurDeLecture : une base illisible ne doit pas
// produire un export PARTIEL présenté comme complet. Un utilisateur qui reçoit
// un export tronqué sans le savoir croit détenir toutes ses données.
func TestExportUserDataRemonteUneErreurDeLecture(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("500 plutôt qu'un export tronqué", func(mt *mtest.T) {
		brancherClientSimule(t, mt.Client)

		mt.AddMockResponses(
			mtest.CreateCursorResponse(0, "arbore.users", mtest.FirstBatch),
			mtest.CreateCommandErrorResponse(mtest.CommandError{
				Code: 13, Message: "not authorized", Name: "Unauthorized",
			}),
		)

		reponse := appelerHandler(exportUserData, "uid-erreur", http.MethodGet, "/users/me/export")

		require.Equal(t, http.StatusInternalServerError, reponse.Code)
		require.Contains(t, reponse.Body.String(), "gardens")
		require.NotContains(t, reponse.Body.String(), "exportDate")
	})
}
