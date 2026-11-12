package main

import "testing"

// La fiabilité est un vocabulaire fermé et ORDONNÉ, et le seuil exigé dépend
// de l'axe (#647 §1, #780 §1).
//
// Elle était une chaîne libre : le client exigeait l'égalité exacte avec `high`
// pendant que la base portait `authoritative`, `authoritative-genus` et
// `derived`. Les 373 valeurs échouaient donc toutes au contrôle de provenance,
// et aucune plante ne pouvait être déclarée adaptée.

func TestFiabiliteAccepteLeVocabulaireFerme(t *testing.T) {
	for _, v := range []string{"low", "moderate", "high"} {
		if !FiabiliteValide(v) {
			t.Errorf("%q devrait appartenir au vocabulaire", v)
		}
	}
}

func TestFiabiliteTolereCasseEtEspaces(t *testing.T) {
	for _, v := range []string{"HIGH", " moderate ", "Low", "\thigh\n"} {
		if !FiabiliteValide(v) {
			t.Errorf("%q devrait être accepté après normalisation", v)
		}
	}
}

// L'ancien vocabulaire de provenance ne doit PAS passer pour une confiance :
// c'est précisément la confusion qui bloquait tout. La base est migrée.
func TestFiabiliteRefuseLAncienVocabulaireDeProvenance(t *testing.T) {
	for _, v := range []string{"", "authoritative", "authoritative-genus", "derived", "unresolved", "medium"} {
		if FiabiliteValide(v) {
			t.Errorf("%q ne devrait PAS appartenir au vocabulaire fermé", v)
		}
	}
}

func TestFiabiliteAuMoinsRespecteLOrdre(t *testing.T) {
	cas := []struct {
		valeur  string
		minimum string
		attendu bool
	}{
		// le plancher accepte tout ce qui est consigné
		{"low", "low", true},
		{"moderate", "low", true},
		{"high", "low", true},
		// le seuil de la toxicité : le genre passe, le déduit non
		{"moderate", "moderate", true},
		{"high", "moderate", true},
		{"low", "moderate", false},
		// le seuil le plus strict
		{"high", "high", true},
		{"moderate", "high", false},
		{"low", "high", false},
		// hors vocabulaire : le plancher, jamais le plafond
		{"authoritative", "moderate", false},
		{"derived", "moderate", false},
		{"authoritative", "low", true},
		// rien de consigné n'atteint aucun seuil, pas même le plancher
		{"", "low", false},
		{"   ", "low", false},
	}
	for _, c := range cas {
		if got := FiabiliteAuMoins(c.valeur, c.minimum); got != c.attendu {
			t.Errorf("FiabiliteAuMoins(%q, %q) = %v, attendu %v",
				c.valeur, c.minimum, got, c.attendu)
		}
	}
}

func TestFiabiliteAuMoinsRefuseUnSeuilInvalide(t *testing.T) {
	if FiabiliteAuMoins("high", "authoritative") {
		t.Error("un seuil hors vocabulaire ne doit jamais être satisfait")
	}
}
