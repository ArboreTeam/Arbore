package main

// purge_user_data_test.go — ce qui efface les données d'un compte. (#725 P1)
//
// `purgeUserData` était à 0 % de couverture, et c'est la fonction la plus
// dangereuse du dépôt : elle est appelée par `deleteUser` (RGPD Art. 17) ET
// par le job de réconciliation (#393), qui tourne tous les dimanches avec
// `--apply` sur la base de production. Un défaut ici efface trop, ou pas
// assez — et « pas assez » est une violation de l'Art. 17 qui ne se voit pas.
//
// Les tests passent par `mtest` en mode Mock : un déploiement simulé qui
// répond des documents en conserve et ENREGISTRE les commandes envoyées.
// C'est exactement le bon niveau pour un effaceur. Ce qui compte n'est pas la
// valeur rendue par Mongo — c'est le filtre, la collection, le type de
// suppression et l'ORDRE. Un vrai mongod ne le dirait pas mieux, et le
// commentaire en tête de `reconcile_guests_test.go` tenait jusqu'ici le
// chemin nominal pour intestable faute de base.

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo/integration/mtest"
)

// mockPurgeOK enchaîne les réponses d'une purge complète qui réussit :
// delete(gardens), delete(consents), find+delete(community_posts),
// delete(users).
func mockPurgeOK(mt *mtest.T, gardens, consents, posts, users int32) {
	mt.AddMockResponses(
		mtest.CreateSuccessResponse(bson.E{Key: "n", Value: gardens}),
		mtest.CreateSuccessResponse(bson.E{Key: "n", Value: consents}),
		mtest.CreateCursorResponse(0, "arbore.community_posts", mtest.FirstBatch),
		mtest.CreateSuccessResponse(bson.E{Key: "n", Value: posts}),
		mtest.CreateSuccessResponse(bson.E{Key: "n", Value: users}),
	)
}

// commandesEnvoyees rend les paires (nom de commande, collection visée) dans
// l'ordre où le pilote les a émises.
func commandesEnvoyees(mt *mtest.T) [][2]string {
	var sent [][2]string
	for _, event := range mt.GetAllStartedEvents() {
		cible, err := event.Command.LookupErr(event.CommandName)
		if err != nil {
			continue
		}
		nom, ok := cible.StringValueOK()
		if !ok {
			continue
		}
		sent = append(sent, [2]string{event.CommandName, nom})
	}
	return sent
}

// TestPurgeUserDataEffaceLesQuatreCollections verrouille le périmètre de
// l'effacement. Une collection oubliée, c'est une donnée personnelle qui
// survit à la suppression du compte.
func TestPurgeUserDataEffaceLesQuatreCollections(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("quatre collections, dans l'ordre", func(mt *mtest.T) {
		mockPurgeOK(mt, 3, 2, 0, 1)

		counts, err := purgeUserData(context.Background(), mt.DB, "uid-a-effacer")
		require.NoError(t, err)
		require.Equal(t,
			purgeCounts{Gardens: 3, Consents: 2, LegacyPosts: 0, Users: 1},
			counts)

		require.Equal(t, [][2]string{
			{"delete", "gardens"},
			{"delete", "consents"},
			{"find", "community_posts"},
			{"delete", "community_posts"},
			{"delete", "users"},
		}, commandesEnvoyees(mt))
	})
}

// TestPurgeUserDataEffaceLeDocumentUtilisateurEnDERNIER n'est pas une
// préférence de style.
//
// Les suppressions sont idempotentes et une purge peut échouer au milieu. Tant
// que le document `users` existe, l'uid reste retrouvable et un rejeu reprend
// le reliquat. Effacé en premier, un échec sur `gardens` laisserait des
// jardins sans propriétaire identifiable — c'est-à-dire exactement ce que le
// job de réconciliation est censé supprimer, mais devenus invisibles pour lui.
func TestPurgeUserDataEffaceLeDocumentUtilisateurEnDERNIER(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("users en dernier", func(mt *mtest.T) {
		mockPurgeOK(mt, 1, 1, 0, 1)
		_, err := purgeUserData(context.Background(), mt.DB, "uid-ordre")
		require.NoError(t, err)

		envoyees := commandesEnvoyees(mt)
		require.NotEmpty(t, envoyees)
		require.Equal(t, [2]string{"delete", "users"}, envoyees[len(envoyees)-1])
	})
}

// TestPurgeUserDataUtiliseDeleteManyEtNonDeleteOne verrouille le constat 1 de
// l'audit #338 : des comptes portent PLUSIEURS documents `users`, et
// `DeleteOne` laissait derrière lui un reliquat avec email, nom et photo.
//
// `limit: 0` dans la commande `delete` est la signature de DeleteMany ;
// `limit: 1` serait DeleteOne.
func TestPurgeUserDataUtiliseDeleteManyEtNonDeleteOne(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("limit 0 partout", func(mt *mtest.T) {
		mockPurgeOK(mt, 2, 0, 0, 2)
		_, err := purgeUserData(context.Background(), mt.DB, "uid-duplique")
		require.NoError(t, err)

		var vus int
		for _, event := range mt.GetAllStartedEvents() {
			if event.CommandName != "delete" {
				continue
			}
			vus++
			deletes, err := event.Command.LookupErr("deletes")
			require.NoError(t, err)
			valeurs, err := deletes.Array().Values()
			require.NoError(t, err)
			require.Len(t, valeurs, 1)
			limite, err := valeurs[0].Document().LookupErr("limit")
			require.NoError(t, err)
			require.EqualValues(t, 0, limite.AsInt64(),
				"une suppression de compte doit effacer TOUS les documents de l'uid")
		}
		require.Equal(t, 4, vus, "quatre suppressions attendues")
	})
}

// TestPurgeUserDataFiltreSurLeBonChampParCollection : `community_posts` porte
// `userId`, hérité des anciennes builds TestFlight, là où les trois autres
// portent `uid`. Filtrer sur `uid` dans `community_posts` ne supprimerait rien
// et ne lèverait aucune erreur — un effacement silencieusement incomplet.
func TestPurgeUserDataFiltreSurLeBonChampParCollection(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("uid partout sauf community_posts", func(mt *mtest.T) {
		const uid = "uid-champs"
		mockPurgeOK(mt, 0, 0, 0, 0)
		_, err := purgeUserData(context.Background(), mt.DB, uid)
		require.NoError(t, err)

		attendu := map[string]string{
			"gardens":         "uid",
			"consents":        "uid",
			"community_posts": "userId",
			"users":           "uid",
		}
		for _, event := range mt.GetAllStartedEvents() {
			if event.CommandName != "delete" {
				continue
			}
			collection := event.Command.Lookup("delete").StringValue()
			champ, connue := attendu[collection]
			require.True(t, connue, "collection inattendue : %s", collection)

			valeurs, err := event.Command.Lookup("deletes").Array().Values()
			require.NoError(t, err)
			filtre := valeurs[0].Document().Lookup("q").Document()
			require.Equal(t, 1, len(filtreCles(t, filtre)),
				"le filtre de %s doit porter exactement un critère", collection)
			require.Equal(t, uid, filtre.Lookup(champ).StringValue(),
				"%s doit être filtrée sur %s", collection, champ)
		}
	})
}

func filtreCles(t *testing.T, doc bson.Raw) []string {
	t.Helper()
	elements, err := doc.Elements()
	require.NoError(t, err)
	cles := make([]string, 0, len(elements))
	for _, element := range elements {
		cles = append(cles, element.Key())
	}
	return cles
}

// TestPurgeUserDataArreteALaPremiereErreurEtNommeLEtape : l'appelant doit
// pouvoir dire QUELLE collection a échoué sans rejouer la séquence. `deleteUser`
// s'en sert pour choisir son message d'erreur.
//
// Et surtout : un échec sur `gardens` ne doit PAS effacer `users`. Le test
// compte les commandes.
func TestPurgeUserDataArreteALaPremiereErreurEtNommeLEtape(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("échec sur gardens", func(mt *mtest.T) {
		mt.AddMockResponses(mtest.CreateCommandErrorResponse(mtest.CommandError{
			Code:    11600,
			Message: "interrupted at shutdown",
			Name:    "InterruptedAtShutdown",
		}))

		counts, err := purgeUserData(context.Background(), mt.DB, "uid-echec")
		require.Error(t, err)

		var stepErr *purgeStepError
		require.True(t, errors.As(err, &stepErr), "l'erreur doit nommer l'étape")
		require.Equal(t, "gardens", stepErr.Step)
		require.Equal(t, purgeCounts{}, counts)

		require.Equal(t, [][2]string{{"delete", "gardens"}}, commandesEnvoyees(mt),
			"rien d'autre ne doit être supprimé après l'échec")
	})
}

// TestDeleteLegacyCommunityDataEffaceLesFichiersDesPostsSupprimes : la
// suppression des documents ne suffit pas, les images restent sur le disque.
// Ce sont des données personnelles, et l'Art. 17 ne s'arrête pas à Mongo.
func TestDeleteLegacyCommunityDataEffaceLesFichiersDesPostsSupprimes(t *testing.T) {
	directory := t.TempDir()
	t.Setenv("COMMUNITY_UPLOADS_DIR", directory)

	garde := filepath.Join(directory, "post-dun-autre.png")
	efface := filepath.Join(directory, "post-a-effacer.jpg")
	require.NoError(t, os.WriteFile(garde, []byte("image"), 0o600))
	require.NoError(t, os.WriteFile(efface, []byte("image"), 0o600))

	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("documents et fichiers", func(mt *mtest.T) {
		mt.AddMockResponses(
			mtest.CreateCursorResponse(0, "arbore.community_posts", mtest.FirstBatch,
				bson.D{{Key: "imageUrl", Value: "https://api.arbore.app/uploads/community/post-a-effacer.jpg"}}),
			mtest.CreateSuccessResponse(bson.E{Key: "n", Value: int32(1)}),
		)

		supprimes, err := deleteLegacyCommunityData(context.Background(), mt.DB, "uid-posts")
		require.NoError(t, err)
		require.EqualValues(t, 1, supprimes)

		_, err = os.Stat(efface)
		require.ErrorIs(t, err, os.ErrNotExist, "l'image du post supprimé doit partir")
		_, err = os.Stat(garde)
		require.NoError(t, err, "les images des autres posts doivent rester")
	})
}

// TestDeleteLegacyCommunityDataRemonteLErreurDeLecture : si la lecture des
// posts échoue, on ne doit RIEN supprimer. Rendre (0, nil) ferait croire à une
// purge réussie sur un compte qui garde ses données.
func TestDeleteLegacyCommunityDataRemonteLErreurDeLecture(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	mt.Run("find en échec", func(mt *mtest.T) {
		mt.AddMockResponses(mtest.CreateCommandErrorResponse(mtest.CommandError{
			Code:    13,
			Message: "not authorized",
			Name:    "Unauthorized",
		}))

		supprimes, err := deleteLegacyCommunityData(context.Background(), mt.DB, "uid-lecture")
		require.Error(t, err)
		require.EqualValues(t, 0, supprimes)

		require.Equal(t, [][2]string{{"find", "community_posts"}}, commandesEnvoyees(mt),
			"aucune suppression ne doit suivre une lecture en échec")
	})
}

// TestPurgeStepErrorExposeLaCauseSousJacente : `Unwrap` n'est pas décoratif.
// Sans lui, un appelant ne pourrait pas distinguer une panne réseau d'une
// erreur d'autorisation — il ne verrait qu'une chaîne de caractères.
func TestPurgeStepErrorExposeLaCauseSousJacente(t *testing.T) {
	cause := errors.New("connexion perdue")
	err := error(&purgeStepError{Step: "gardens", Err: cause})

	require.ErrorIs(t, err, cause, "la cause doit rester atteignable par errors.Is")
	require.Equal(t, "gardens: connexion perdue", err.Error())
}
