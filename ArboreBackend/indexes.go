// indexes.go
//
// Index MongoDB créés au démarrage (audit #338, constat 7).
//
// Avant ce fichier, la seule collection indexée l'était sur `_id` : toute requête
// filtrant sur `uid` provoquait un balayage complet de la collection. Le cas le
// plus coûteux est `checkUserBannedFromDB`, appelé par le middleware Firebase à
// CHAQUE requête authentifiée — soit un scan de `users` par requête d'API.
package main

import (
	"context"
	"log"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// indexSpec décrit un index à garantir, avec la raison de son existence pour que
// personne ne le supprime en pensant qu'il ne sert à rien.
type indexSpec struct {
	collection string
	keys       bson.D
	name       string
	reason     string
}

// requiredIndexes liste les index attendus sur une base Arbore.
//
// ⚠️ `users.uid` n'est volontairement PAS unique ici. La contrainte d'unicité est
// ce qu'il faudrait, mais la base de production contient déjà des documents
// dupliqués (cf. #338 constat 1 : 48 documents pour 25 uid distincts) et une
// création d'index unique échouerait avec E11000. L'unicité doit être ajoutée
// par le correctif du constat 1, APRÈS la migration de dédoublonnage.
var requiredIndexes = []indexSpec{
	{
		collection: "users",
		keys:       bson.D{{Key: "uid", Value: 1}},
		name:       "uid_1",
		reason:     "vérification de ban à chaque requête authentifiée + lecture/écriture de profil",
	},
	{
		collection: "gardens",
		keys:       bson.D{{Key: "uid", Value: 1}, {Key: "updatedAt", Value: -1}},
		name:       "uid_1_updatedAt_-1",
		reason:     "listGardens (filtre uid + tri updatedAt) ; sert aussi de préfixe aux requêtes sur uid seul",
	},
	{
		collection: "consents",
		keys:       bson.D{{Key: "uid", Value: 1}, {Key: "timestamp", Value: -1}},
		name:       "uid_1_timestamp_-1",
		reason:     "getUserConsents / getLatestUserConsents (filtre uid + tri timestamp)",
	},
}

// La collection `plants` n'apparaît pas ci-dessus : sa seule recherche par nom
// (generateAndInsertPlant) est une regex insensible à la casse, qu'un index
// classique ne peut pas exploiter efficacement. Si ce chemin devient chaud, la
// bonne réponse est un champ `nameNormalized` indexé, pas un index sur `name`.

// ensureIndexes crée les index manquants sur les bases fournies. L'opération est
// idempotente : MongoDB ignore une création d'index déjà satisfaite.
//
// Un échec est journalisé mais NE bloque pas le démarrage : sans index l'API
// reste fonctionnelle (seulement plus lente), et un incident Mongo passager ne
// doit pas empêcher le backend de repartir.
func ensureIndexes(ctx context.Context, databases map[string]*mongo.Database) {
	for label, db := range databases {
		if db == nil {
			continue
		}
		for _, spec := range requiredIndexes {
			model := mongo.IndexModel{
				Keys:    spec.keys,
				Options: options.Index().SetName(spec.name),
			}
			if _, err := db.Collection(spec.collection).Indexes().CreateOne(ctx, model); err != nil {
				log.Printf("⚠️  Index %s.%s (%s) non créé sur la base %s: %v",
					spec.collection, spec.name, spec.reason, label, err)
				continue
			}
		}
		log.Printf("✅ Index vérifiés sur la base %s", label)
	}
}

// ensureIndexesAtStartup applique ensureIndexes aux bases connectées, avec un
// délai borné pour ne pas retarder indéfiniment le démarrage du serveur.
func ensureIndexesAtStartup() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	databases := map[string]*mongo.Database{}
	if client != nil {
		databases[prodDBName] = client.Database(prodDBName)
	}
	if testClient != nil {
		databases[testDBName] = testClient.Database(testDBName)
	}
	ensureIndexes(ctx, databases)
}
