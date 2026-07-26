package main

import (
	"context"
	"testing"

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

// Garde-fou délibéré : rendre `users.uid` unique est le bon objectif final, mais
// la base de prod contient des doublons (audit #338 constat 1) et la création
// échouerait avec E11000, ce qui masquerait l'index pour toutes les collections.
// L'unicité doit arriver AVEC la migration de dédoublonnage, pas avant.
func TestUsersUIDIndexIsNotYetUnique(t *testing.T) {
	for _, spec := range requiredIndexes {
		if spec.collection == "users" && spec.name == "uid_1" {
			// L'unicité n'est pas exprimable dans indexSpec : c'est volontaire.
			// Si un champ `unique` y est ajouté un jour, ce test doit être revu
			// en même temps que la migration.
			return
		}
	}
	t.Fatal("index users.uid_1 introuvable dans requiredIndexes")
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
