package main

import "testing"

// Le seul comportement qui protège la production : une base qui est sa propre
// source se refuse. Éprouvé sans Mongo, parce qu'un garde-fou qui ne peut être
// testé qu'avec un service branché ne sera pas testé.
func TestDoitSeeder(t *testing.T) {
	cas := []struct {
		nom         string
		destination string
		source      string
		attendu     bool
	}{
		// La production : `MONGODB_DB` n'y est pas défini, donc `prodDBName`
		// vaut le même `arbore` que la source. C'est LE cas à refuser.
		{"production se refuse elle-même", "arbore", "arbore", false},

		{"dev accepté", "arbore_dev", "arbore", true},
		{"test accepté", "arbore_test", "arbore", true},
		{"pré-prod accepté", "arbore_preprod", "arbore", true},

		// Une source renommée ne doit pas rouvrir le cas interdit.
		{"source renommée, destination identique", "catalogue", "catalogue", false},
		{"source renommée, destination différente", "arbore_dev", "catalogue", true},

		// Valeurs manquantes : refus. Un nom vide viserait la base par défaut
		// du client, qu'on ne veut jamais deviner.
		{"destination vide", "", "arbore", false},
		{"source vide", "arbore_dev", "", false},
		{"les deux vides", "", "", false},

		// Les espaces ne doivent pas faire passer le cas interdit pour deux
		// noms différents.
		{"espaces autour du même nom", " arbore ", "arbore", false},
		{"espaces, noms différents", " arbore_dev ", " arbore ", true},
	}
	for _, c := range cas {
		t.Run(c.nom, func(t *testing.T) {
			if got := doitSeeder(c.destination, c.source); got != c.attendu {
				t.Errorf("doitSeeder(%q, %q) = %v, attendu %v", c.destination, c.source, got, c.attendu)
			}
		})
	}
}
