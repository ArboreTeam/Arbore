package main

import (
	"bytes"
	"context"
	"log"
	"strings"
	"testing"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

// Les requêtes filtrant sur `uid` sont sur le chemin chaud de chaque requête
// authentifiée : ce test verrouille la présence des index correspondants pour
// qu'une suppression accidentelle soit visible en CI.
func TestRequiredIndexesCoverUIDLookups(t *testing.T) {
	wantFirstKey := map[string]string{
		"users":    "uid",
		"gardens":  "uid",
		"consents": "uid",
	}

	seen := map[string]bool{}
	for _, spec := range requiredIndexes {
		if len(spec.keys) == 0 {
			t.Fatalf("index %q sur %s n'a aucune clé", spec.name, spec.collection)
		}
		if spec.name == "" {
			t.Fatalf("index sur %s doit porter un nom explicite", spec.collection)
		}
		if spec.reason == "" {
			t.Fatalf("index %s.%s doit documenter sa raison d'être", spec.collection, spec.name)
		}
		// Le premier champ détermine si l'index est utilisable pour un filtre `uid`.
		if got := spec.keys[0].Key; got != wantFirstKey[spec.collection] {
			t.Errorf("index %s.%s: première clé %q, attendu %q",
				spec.collection, spec.name, got, wantFirstKey[spec.collection])
		}
		seen[spec.collection] = true
	}

	for collection := range wantFirstKey {
		if !seen[collection] {
			t.Errorf("aucun index sur uid pour la collection %q", collection)
		}
	}
}

// `users.uid` DOIT être unique : c'est la garantie structurelle qui empêche le
// retour des doublons (audit #338 constat 1). Le code applicatif — `createUser`
// en upsert — évite d'en créer, mais seul l'index rend la duplication
// impossible, y compris pour un script, une écriture manuelle ou un futur
// chemin de code qui oublierait la règle.
//
// Ce test remplace `TestUsersUIDIndexIsNotYetUnique`, qui verrouillait
// l'ABSENCE d'unicité tant que la production contenait des doublons. La
// migration `scripts/dedupe-users.js` ayant été appliquée (48 → 25 documents,
// 0 doublon), la contrainte peut désormais être posée.
func TestUsersUIDIndexIsUnique(t *testing.T) {
	for _, spec := range requiredIndexes {
		if spec.collection == "users" && spec.name == "uid_1" {
			if !spec.unique {
				t.Fatal("users.uid_1 doit être unique : sans cette contrainte, rien n'empêche structurellement le retour des doublons")
			}
			return
		}
	}
	t.Fatal("index users.uid_1 introuvable dans requiredIndexes")
}

// Les autres index ne doivent PAS être uniques : un utilisateur a plusieurs
// jardins et plusieurs consentements. Une unicité posée là casserait l'écriture.
func TestOnlyUsersIndexIsUnique(t *testing.T) {
	for _, spec := range requiredIndexes {
		if spec.collection == "users" {
			continue
		}
		if spec.unique {
			t.Errorf("%s.%s ne doit pas être unique : un uid a légitimement plusieurs documents",
				spec.collection, spec.name)
		}
	}
}

// Le message d'erreur d'un conflit d'options doit contenir une commande
// mongosh copiable telle quelle : c'est tout son intérêt pour l'exploitant.
// L'ordre des champs compte dans un index composé.
func TestFormatIndexKeysPreservesOrder(t *testing.T) {
	for _, test := range []struct {
		name string
		keys bson.D
		want string
	}{
		{
			name: "cle simple",
			keys: bson.D{{Key: "uid", Value: 1}},
			want: "{uid: 1}",
		},
		{
			name: "cle composee, ordre significatif",
			keys: bson.D{{Key: "uid", Value: 1}, {Key: "updatedAt", Value: -1}},
			want: "{uid: 1, updatedAt: -1}",
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			if got := formatIndexKeys(test.keys); got != test.want {
				t.Errorf("got %q, want %q", got, test.want)
			}
		})
	}
}

// Les deux codes de conflit doivent produire le message actionnable.
//
// Test écrit après coup : `logIndexFailure` ne traitait que le code 85
// (IndexOptionsConflict), or MongoDB renvoie **86** (IndexKeySpecsConflict)
// quand on ajoute `unique: true` à un index existant. Constaté en production sur
// `arbore_test` : le cas réel tombait dans la branche par défaut, donc affichait
// l'erreur brute au lieu de la commande à exécuter.
func TestLogIndexFailureHandlesBothConflictCodes(t *testing.T) {
	spec := indexSpec{
		collection: "users",
		keys:       bson.D{{Key: "uid", Value: 1}},
		name:       "uid_1",
		unique:     true,
		reason:     "test",
	}

	var buffer bytes.Buffer
	original := log.Writer()
	log.SetOutput(&buffer)
	t.Cleanup(func() { log.SetOutput(original) })

	for _, test := range []struct {
		name string
		code int32
	}{
		{name: "IndexOptionsConflict", code: mongoErrIndexOptionsConflict},
		{name: "IndexKeySpecsConflict", code: mongoErrIndexKeySpecsConflict},
	} {
		t.Run(test.name, func(t *testing.T) {
			buffer.Reset()
			logIndexFailure("arbore", spec, mongo.CommandError{Code: test.code, Message: "conflit"})

			output := buffer.String()
			// Le message doit contenir la commande de remplacement, copiable.
			if !strings.Contains(output, `dropIndex("uid_1")`) {
				t.Errorf("code %d : la commande dropIndex manque.\n%s", test.code, output)
			}
			if !strings.Contains(output, "unique:true") {
				t.Errorf("code %d : la commande createIndex doit préciser unique:true.\n%s", test.code, output)
			}
		})
	}
}

// Un doublon doit renvoyer vers la migration, pas vers un remplacement d'index.
func TestLogIndexFailurePointsToMigrationOnDuplicateKey(t *testing.T) {
	spec := indexSpec{collection: "users", keys: bson.D{{Key: "uid", Value: 1}}, name: "uid_1", unique: true}

	var buffer bytes.Buffer
	original := log.Writer()
	log.SetOutput(&buffer)
	t.Cleanup(func() { log.SetOutput(original) })

	logIndexFailure("arbore", spec, mongo.CommandError{Code: mongoErrDuplicateKey, Message: "E11000"})

	output := buffer.String()
	if !strings.Contains(output, "dedupe-users.js") {
		t.Errorf("un E11000 doit renvoyer vers la migration.\n%s", output)
	}
	if strings.Contains(output, "dropIndex") {
		t.Errorf("un E11000 ne doit PAS suggérer de remplacer l'index : les données violent la contrainte.\n%s", output)
	}
}

// ensureIndexes doit ignorer une base nil sans paniquer : `testClient` est nil
// quand MONGODB_URI_TEST n'est pas défini.
func TestEnsureIndexesSkipsNilDatabase(t *testing.T) {
	defer func() {
		if recovered := recover(); recovered != nil {
			t.Fatalf("ensureIndexes a paniqué sur une base nil: %v", recovered)
		}
	}()
	ensureIndexes(context.Background(), map[string]*mongo.Database{
		"absente": nil,
	})
}
