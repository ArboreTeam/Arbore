// indexes.go
//
// Index MongoDB créés au démarrage (audit #338, constat 7).
//
// Avant ce fichier, la seule collection indexée l'était sur `_id` : toute requête
// filtrant sur `uid` provoquait un balayage complet de la collection. Le cas le
// plus coûteux est `loadAccessProfileFromDB` (anciennement `checkUserBannedFromDB`),
// appelé par le middleware Firebase à CHAQUE requête authentifiée — soit un scan
// de `users` par requête d'API.
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
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
	unique     bool
	reason     string
}

// requiredIndexes liste les index attendus sur une base Arbore.
var requiredIndexes = []indexSpec{
	{
		collection: "users",
		keys:       bson.D{{Key: "uid", Value: 1}},
		name:       "uid_1",
		unique:     true,
		reason:     "vérification de ban à chaque requête authentifiée + lecture/écriture de profil ; l'unicité est la garantie structurelle contre le retour des doublons (#338 constat 1)",
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
				Options: options.Index().SetName(spec.name).SetUnique(spec.unique),
			}
			if _, err := db.Collection(spec.collection).Indexes().CreateOne(ctx, model); err != nil {
				logIndexFailure(label, spec, err)
				continue
			}
		}
		log.Printf("✅ Index vérifiés sur la base %s", label)
	}
}

// Codes d'erreur MongoDB rencontrés à la création d'index. Ils méritent des
// messages distincts : l'un se corrige par une commande d'exploitation, l'autre
// signale que des données violent la contrainte.
const (
	// MongoDB renvoie DEUX codes distincts pour « un index de ce nom existe déjà
	// avec d'autres caractéristiques », et lequel dépend de ce qui diffère :
	//   85 — les *options* divergent (unique, partialFilterExpression…)
	//   86 — les *specs de clé* divergent
	//
	// Observé en production : ajouter `unique: true` à un index existant renvoie
	// 86, pas 85. Ne traiter que 85 faisait tomber le cas réel dans la branche
	// par défaut, donc afficher l'erreur brute au lieu de la commande à exécuter.
	mongoErrIndexOptionsConflict  = 85
	mongoErrIndexKeySpecsConflict = 86
	mongoErrDuplicateKey          = 11000
)

// formatIndexKeys rend une clé d'index sous la forme attendue par mongosh, pour
// que le message d'erreur contienne une commande directement copiable.
// L'ordre des champs est significatif dans un index composé, d'où le parcours du
// bson.D plutôt qu'une conversion en map.
func formatIndexKeys(keys bson.D) string {
	parts := make([]string, 0, len(keys))
	for _, element := range keys {
		parts = append(parts, fmt.Sprintf("%s: %v", element.Key, element.Value))
	}
	return "{" + strings.Join(parts, ", ") + "}"
}

// logIndexFailure explique quoi faire, plutôt que de recracher l'erreur brute.
//
// Le cas important est le passage de `users.uid` en unique : l'index non unique
// existe déjà en production, et MongoDB refuse d'en changer les options en
// place. Le remplacement est une opération d'exploitation délibérée, PAS quelque
// chose que le démarrage doit tenter : un `drop` suivi d'un `create` qui échoue
// laisserait la collection sans aucun index, donc en balayage complet à chaque
// requête authentifiée — exactement le problème que le constat 7 a corrigé.
func logIndexFailure(label string, spec indexSpec, err error) {
	var cmdErr mongo.CommandError
	isConflict := errors.As(err, &cmdErr) &&
		(cmdErr.Code == mongoErrIndexOptionsConflict || cmdErr.Code == mongoErrIndexKeySpecsConflict)

	switch {
	case isConflict:
		log.Printf("⚠️  Index %s.%s sur la base %s : un index de même nom existe avec d'autres caractéristiques (unique attendu = %t).",
			spec.collection, spec.name, label, spec.unique)
		log.Printf("    Remplacement manuel requis, collection vide de doublons au préalable :")
		log.Printf(`    db.%s.dropIndex("%s"); db.%s.createIndex(%s, {name:"%s", unique:%t})`,
			spec.collection, spec.name, spec.collection, formatIndexKeys(spec.keys), spec.name, spec.unique)
	case errors.As(err, &cmdErr) && cmdErr.Code == mongoErrDuplicateKey:
		log.Printf("❌ Index %s.%s sur la base %s : des doublons violent l'unicité.",
			spec.collection, spec.name, label)
		log.Printf("    Lancer d'abord la migration : ArboreBackend/scripts/dedupe-users.js")
	default:
		log.Printf("⚠️  Index %s.%s (%s) non créé sur la base %s: %v",
			spec.collection, spec.name, spec.reason, label, err)
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
