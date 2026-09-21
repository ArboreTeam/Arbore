package main

import (
	"bufio"
	"os"
	"strings"
	"testing"
)

// catalog_reel_test — issue #554.
//
// Les autres tests utilisent un catalogue inventé, aux noms botaniques propres.
// Le VRAI catalogue ne leur ressemble pas : ce sont des libellés commerciaux,
// relevés en production le 2026-09-21.
//
//	Calathéa Varié H. 75 cm pot D.19 cm
//	Echeveria + cache-pot céramique
//	Scindapsus N’Joy            (apostrophe typographique)
//	Nephrolepis – Pot en terre  (tiret demi-cadratin)
//	Pelargonium × hortorum      (signe multiplié)
//	Asparagus - La              (libellé tronqué à la source)
//
// Un appariement qui marche sur « Monstera deliciosa » peut échouer sur tout
// ça. D'où ce fichier, qui confronte la logique aux noms réels et aux
// formulations qu'un utilisateur emploie vraiment.

func catalogueReel(t *testing.T) []ficheLegere {
	t.Helper()
	f, err := os.Open("testdata/noms_catalogue.txt")
	if err != nil {
		t.Skipf("jeu de noms réels absent : %v", err)
	}
	defer func() { _ = f.Close() }()

	var fiches []ficheLegere
	sc := bufio.NewScanner(f)
	for i := 0; sc.Scan(); i++ {
		nom := strings.TrimSpace(sc.Text())
		if nom == "" {
			continue
		}
		fiches = append(fiches, ficheLegere{
			ID:          string(rune('A'+i%26)) + strings.Repeat("x", i/26),
			Nom:         nom,
			NomNormalis: normaliserNom(nom),
		})
	}
	return fiches
}

// Aucun nom réel ne doit se normaliser en chaîne vide : une fiche invisible à
// l'appariement ne serait jamais ancrée, sans que rien ne le signale.
func TestCatalogueReel_AucunNomNeSeNormaliseEnVide(t *testing.T) {
	for _, f := range catalogueReel(t) {
		if f.NomNormalis == "" {
			t.Errorf("« %s » se normalise en chaîne vide", f.Nom)
		}
	}
}

// Deux fiches distinctes ne doivent pas se normaliser pareil : l'appariement
// rendrait alors l'une pour l'autre, au hasard de l'ordre de parcours.
func TestCatalogueReel_PasDeCollisionDeNormalisation(t *testing.T) {
	vus := map[string]string{}
	for _, f := range catalogueReel(t) {
		if autre, deja := vus[f.NomNormalis]; deja {
			t.Errorf("collision : « %s » et « %s » → %q", autre, f.Nom, f.NomNormalis)
		}
		vus[f.NomNormalis] = f.Nom
	}
}

// Le cœur du sujet : ce qu'un utilisateur écrit vraiment doit trouver la fiche.
func TestCatalogueReel_FormulationsDUtilisateur(t *testing.T) {
	fiches := catalogueReel(t)
	cas := []struct {
		saisie  string
		attendu string // préfixe du nom de fiche attendu
	}{
		{"monstera", "Monstera"},
		{"mon monstera jaunit", "Monstera"},
		{"Monstera deliciosa", "Monstera"},
		{"sansevieria", "Sansevieria"},
		{"ma sansevieria trifasciata", "Sansevieria Trifasciata"},
		{"zamioculcas", "Zamioculcas"},
		{"mon ficus elastica perd ses feuilles", "Ficus elastica"},
		{"dracaena marginata", "Dracaena marginata"},
		{"lavandula angustifolia", "Lavandula angustifolia"},
		{"aloe", ""}, // absent du catalogue : ne doit rien trouver
		{"acer palmatum", "Acer palmatum"},
		{"kentia forsteriana", "Kentia forsteriana"},
		{"philodendron scandens", "Philodendron Scandens"},
		{"chamaedorea", "Chamaedorea"},
		{"haworthia", "Haworthia"},
	}
	for _, c := range cas {
		f, ok := trouverFiche(fiches, c.saisie)
		switch {
		case c.attendu == "" && ok:
			t.Errorf("« %s » ne devrait rien apparier, obtenu « %s »", c.saisie, f.Nom)
		case c.attendu != "" && !ok:
			t.Errorf("« %s » devrait apparier une fiche « %s… », rien trouvé", c.saisie, c.attendu)
		case c.attendu != "" && ok && !strings.HasPrefix(strings.ToLower(f.Nom), strings.ToLower(c.attendu)):
			t.Errorf("« %s » → « %s », attendu une fiche « %s… »", c.saisie, f.Nom, c.attendu)
		}
	}
}

// Les caractères exotiques des libellés commerciaux ne doivent pas empêcher
// l'appariement quand l'utilisateur écrit la même chose en clavier ordinaire.
func TestCatalogueReel_CaracteresExotiques(t *testing.T) {
	fiches := catalogueReel(t)
	cas := map[string]string{
		"scindapsus n'joy":       "Scindapsus",  // apostrophe droite vs typographique
		"pelargonium x hortorum": "Pelargonium", // « x » vs « × »
		"nephrolepis":            "Nephrolepis", // tiret demi-cadratin dans la fiche
		"echeveria":              "Echeveria",   // « + » dans la fiche
		"kalanchoe":              "KALANCHOE",   // fiche en capitales
		"aglaonema":              "Aglaon",      // accent dans certaines fiches
		"calathea":               "Calath",      // idem
	}
	for saisie, attendu := range cas {
		f, ok := trouverFiche(fiches, saisie)
		if !ok {
			t.Errorf("« %s » devrait apparier « %s… », rien trouvé", saisie, attendu)
			continue
		}
		if !strings.HasPrefix(strings.ToLower(f.Nom), strings.ToLower(attendu)) {
			t.Errorf("« %s » → « %s », attendu « %s… »", saisie, f.Nom, attendu)
		}
	}
}

// Le relevé dans du texte libre, sur les vrais noms.
func TestCatalogueReel_ReleveDansUneConversation(t *testing.T) {
	fiches := catalogueReel(t)
	vues := fichesMentionnees(fiches,
		"j'ai un monstera et un zamioculcas dans le salon, lequel arroser le plus ?", 3)
	if len(vues) < 2 {
		t.Fatalf("2 plantes citées doivent être relevées, obtenu %d (%v)", len(vues), noms(vues))
	}
}

// Un message sans plante ne doit rien relever, sinon chaque conversation
// traînerait un contexte hors sujet.
func TestCatalogueReel_PasDeFauxPositifSurUneQuestionGenerale(t *testing.T) {
	for _, message := range []string{
		"quand faut-il rempoter ?",
		"quelle terre pour un balcon exposé au nord ?",
		"mes feuilles jaunissent, que faire ?",
		"bonjour",
	} {
		if vues := fichesMentionnees(catalogueReel(t), message, 3); len(vues) > 0 {
			t.Errorf("« %s » ne cite aucune plante, relevé %v", message, noms(vues))
		}
	}
}
