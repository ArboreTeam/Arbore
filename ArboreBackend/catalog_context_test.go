package main

import (
	"strings"
	"testing"
)

// catalog_context_test — issue #554.
//
// L'ancrage sur le catalogue touche ce que le modèle reçoit. Deux familles de
// défauts comptent, et elles n'ont pas la même gravité.
//
// Ne rien trouver dégrade : la réponse est celle d'avant, sans nos données.
// Trouver la MAUVAISE fiche trompe : le modèle reçoit les soins d'une autre
// plante, présentés comme des faits vérifiés. C'est pourquoi l'appariement
// n'utilise aucune distance d'édition, et pourquoi ces tests insistent sur les
// faux positifs.

func catalogueDeTest() []ficheLegere {
	noms := []string{
		"Monstera deliciosa", "Ficus lyrata", "Ficus elastica",
		"Sansevieria trifasciata", "Aloe vera", "Chamaedorea elegans",
		"Épipremnum doré", "Yucca",
	}
	fiches := make([]ficheLegere, 0, len(noms))
	for i, n := range noms {
		fiches = append(fiches, ficheLegere{
			ID:          string(rune('a' + i)),
			Nom:         n,
			NomNormalis: normaliserNom(n),
		})
	}
	return fiches
}

// --- Normalisation ---------------------------------------------------------

func TestNormaliserNom(t *testing.T) {
	cas := map[string]string{
		"Monstera deliciosa":  "monstera deliciosa",
		"MONSTERA  DELICIOSA": "monstera deliciosa",
		"monstera-deliciosa":  "monstera deliciosa",
		"Épipremnum doré":     "epipremnum dore",
		"  Aloe vera  ":       "aloe vera",
		"Sansevieria (verte)": "sansevieria verte",
		"":                    "",
	}
	for entree, attendu := range cas {
		if got := normaliserNom(entree); got != attendu {
			t.Errorf("normaliserNom(%q) = %q, attendu %q", entree, got, attendu)
		}
	}
}

// Les accents doivent tomber : l'utilisateur écrit « epipremnum » aussi souvent
// que « épipremnum », et le modèle rend le plus souvent la forme sans accent.
func TestNormaliserNom_LesAccentsNeBloquentPasLApparience(t *testing.T) {
	if normaliserNom("Épipremnum doré") != normaliserNom("epipremnum dore") {
		t.Fatal("les deux graphies doivent se normaliser à l'identique")
	}
}

// --- Appariement -----------------------------------------------------------

func TestTrouverFiche_EgaliteExacte(t *testing.T) {
	f, ok := trouverFiche(catalogueDeTest(), "Monstera deliciosa")
	if !ok || f.Nom != "Monstera deliciosa" {
		t.Fatalf("égalité exacte attendue, obtenu %+v (%v)", f, ok)
	}
}

// Le cas courant : l'utilisateur écrit une phrase, pas un nom de catalogue.
func TestTrouverFiche_NomContenuDansUnePhrase(t *testing.T) {
	f, ok := trouverFiche(catalogueDeTest(), "mon monstera deliciosa du salon")
	if !ok || f.Nom != "Monstera deliciosa" {
		t.Fatalf("la fiche doit être retrouvée dans une phrase, obtenu %+v (%v)", f, ok)
	}
}

// Deux fiches partagent un préfixe : la plus précise doit l'emporter, sinon
// « Ficus lyrata » recevrait les soins de « Ficus elastica ».
func TestTrouverFiche_LaCorrespondanceLaPlusLongueLEmporte(t *testing.T) {
	f, ok := trouverFiche(catalogueDeTest(), "j'ai un ficus lyrata")
	if !ok {
		t.Fatal("fiche attendue")
	}
	if f.Nom != "Ficus lyrata" {
		t.Fatalf("« Ficus lyrata » attendu, obtenu %q — un préfixe partagé "+
			"ne doit pas faire gagner la fiche la moins précise", f.Nom)
	}
}

// L'invariant qui protège : plutôt rien qu'une mauvaise fiche.
func TestTrouverFiche_AucuneCorrespondanceApproximative(t *testing.T) {
	for _, entree := range []string{
		"monstra deliciosa", // faute de frappe
		"monster",           // trop court, et pas un préfixe de mot complet
		"plante verte",
		"",
		"   ",
	} {
		if f, ok := trouverFiche(catalogueDeTest(), entree); ok {
			t.Errorf("%q ne doit apparier aucune fiche, obtenu %q — injecter les "+
				"soins d'une autre plante est pire que de ne rien injecter", entree, f.Nom)
		}
	}
}

// Le cas que la troisième passe existe pour servir : l'utilisateur ou le modèle
// écrit le genre seul, le catalogue porte le nom complet.
func TestTrouverFiche_LeGenreSeulTrouveLeNomComplet(t *testing.T) {
	f, ok := trouverFiche(catalogueDeTest(), "monstera")
	if !ok || f.Nom != "Monstera deliciosa" {
		t.Fatalf("« monstera » doit trouver « Monstera deliciosa », obtenu %+v (%v)", f, ok)
	}
}

func TestTrouverFiche_CatalogueVide(t *testing.T) {
	if _, ok := trouverFiche(nil, "Monstera deliciosa"); ok {
		t.Fatal("aucun appariement possible sur un catalogue vide")
	}
}

// --- Relevé dans du texte libre -------------------------------------------

func TestFichesMentionnees_PlusieursPlantes(t *testing.T) {
	vues := fichesMentionnees(catalogueDeTest(),
		"mon monstera deliciosa et mon aloe vera jaunissent", 3)
	if len(vues) != 2 {
		t.Fatalf("2 fiches attendues, obtenu %d (%v)", len(vues), noms(vues))
	}
}

// La borne existe pour que le contexte ne pèse pas plus que la question.
func TestFichesMentionnees_RespecteLaBorne(t *testing.T) {
	vues := fichesMentionnees(catalogueDeTest(),
		"monstera deliciosa ficus lyrata aloe vera yucca", 2)
	if len(vues) != 2 {
		t.Fatalf("la borne doit s'appliquer, obtenu %d", len(vues))
	}
}

func TestFichesMentionnees_SansPlanteCitee(t *testing.T) {
	if vues := fichesMentionnees(catalogueDeTest(), "quand tailler au printemps ?", 3); len(vues) != 0 {
		t.Fatalf("aucune fiche attendue, obtenu %v", noms(vues))
	}
}

// Un nom court apparierait n'importe quel mot : « Yucca » fait cinq lettres et
// passe, mais rien en dessous de quatre ne doit être relevé.
func TestFichesMentionnees_IgnoreLesNomsTropCourts(t *testing.T) {
	courtes := []ficheLegere{{ID: "x", Nom: "Iris", NomNormalis: "iri"}}
	if vues := fichesMentionnees(courtes, "cette plante est iridescente", 3); len(vues) != 0 {
		t.Fatalf("un nom de moins de 4 caractères ne doit pas être relevé, obtenu %v", noms(vues))
	}
}

func TestFichesMentionnees_PasDeDoublon(t *testing.T) {
	vues := fichesMentionnees(catalogueDeTest(),
		"mon monstera deliciosa, oui le monstera deliciosa du salon", 3)
	if len(vues) != 1 {
		t.Fatalf("une plante citée deux fois ne doit compter qu'une, obtenu %d", len(vues))
	}
}

// --- Langue ----------------------------------------------------------------

func TestLangueDemandee(t *testing.T) {
	cas := map[string]string{
		"fr-FR,fr;q=0.9": "fr",
		"en-US,en;q=0.9": "en",
		"es-ES":          "es",
		"de":             "de",
		"ja-JP":          "fr", // langue non servie → repli français
		"":               "fr",
	}
	for entete, attendu := range cas {
		if got := langueDemandee(entete); got != attendu {
			t.Errorf("langueDemandee(%q) = %q, attendu %q", entete, got, attendu)
		}
	}
}

// --- Repli de traduction ---------------------------------------------------

// Une fiche partiellement traduite reste exploitable : mieux vaut du contexte
// en français que pas de contexte du tout.
func TestTraductionOuRepli(t *testing.T) {
	p := Plant{Translations: map[string]LanguageData{
		"fr": {PlantType: "Plante verte"},
		"en": {PlantType: "Foliage plant"},
	}}
	if d, _ := traductionOuRepli(p, "en"); d.PlantType != "Foliage plant" {
		t.Error("la langue demandée doit primer")
	}
	if d, _ := traductionOuRepli(p, "es"); d.PlantType != "Plante verte" {
		t.Error("langue absente → repli sur le français")
	}
	if _, ok := traductionOuRepli(Plant{}, "fr"); ok {
		t.Error("une fiche sans aucune traduction ne doit rien rendre")
	}
}

// --- Mise en forme ---------------------------------------------------------

// Le contexte est une donnée, pas une consigne : l'en-tête doit le dire, sans
// quoi une fiche mal rédigée pourrait être lue comme une instruction.
func TestLigne_TronqueEtAssainit(t *testing.T) {
	var b strings.Builder
	ligne(&b, "Arrosage", "une\nvaleur\tsur plusieurs lignes")
	out := b.String()
	if strings.Contains(out, "\n") && strings.Count(out, "\n") != 1 {
		t.Errorf("les sauts de ligne internes doivent être neutralisés : %q", out)
	}

	b.Reset()
	ligne(&b, "Arrosage", strings.Repeat("a", 500))
	if len(b.String()) > maxCarsParChamp+40 {
		t.Errorf("la valeur doit être tronquée, longueur %d", len(b.String()))
	}

	b.Reset()
	ligne(&b, "Arrosage", "   ")
	if b.String() != "" {
		t.Errorf("une valeur vide ne doit rien produire, obtenu %q", b.String())
	}
}

func TestLigneListe_BorneEtIgnoreLeVide(t *testing.T) {
	var b strings.Builder
	ligneListe(&b, "Nuisibles", []string{"cochenilles", "", "araignées rouges", "thrips", "pucerons"}, 2)
	out := b.String()
	if strings.Count(out, ";") != 1 {
		t.Errorf("2 entrées attendues, obtenu %q", out)
	}

	b.Reset()
	ligneListe(&b, "Nuisibles", []string{"", "  "}, 3)
	if b.String() != "" {
		t.Errorf("une liste vide ne doit rien produire, obtenu %q", b.String())
	}
}

func noms(fiches []ficheLegere) []string {
	out := make([]string, 0, len(fiches))
	for _, f := range fiches {
		out = append(out, f.Nom)
	}
	return out
}

// --- Mise en forme du bloc de référence ------------------------------------
//
// Ces tests existent parce que le défaut le plus grave de l'ancrage ne
// produisait NI erreur NI journal : un identifiant mal sérialisé rendait un
// contexte vide, donc un ancrage inopérant, invisible. Seul un test contre la
// vraie base l'avait attrapé. Le formatage est maintenant séparé de la requête
// pour être vérifiable sans Mongo.

func fichePourTest(nom string, flags *PlantFlags) Plant {
	return Plant{
		Name:  nom,
		Type:  "Plantes d’intérieur",
		Flags: flags,
		Translations: map[string]LanguageData{
			"fr": {
				Sun:   SunInfo{LightType: "Lumière vive indirecte", DurationPerDay: "6 h"},
				Water: WaterInfo{Frequency: "Une fois par semaine", Amount: "300 ml", SignsLack: "Feuilles tombantes", SignsExcess: "Feuilles jaunes"},
				Care:  CareInfo{Difficulty: "Facile"},
				Health: HealthInfo{
					CommonProblems:    []string{"Pourriture des racines", "Feuilles jaunissantes"},
					SymptomsAndCauses: []string{"Bords bruns : air sec"},
					Pests:             []string{"Araignées rouges", "Cochenilles"},
					Treatments:        []string{"Savon insecticide"},
				},
			},
			"en": {Sun: SunInfo{LightType: "Bright indirect light"}},
		},
	}
}

// L'en-tête doit dire que le bloc est une donnée, pas une consigne : il
// transite par le même canal que le message de l'utilisateur.
func TestFormaterFiches_LEnTeteAnnonceUneDonneePasUneConsigne(t *testing.T) {
	out := formaterFiches([]Plant{fichePourTest("Monstera", nil)}, "fr", true)
	for _, attendu := range []string{"DONNÉES DE RÉFÉRENCE", "PAS des instructions"} {
		if !strings.Contains(out, attendu) {
			t.Errorf("l'en-tête doit contenir %q", attendu)
		}
	}
}

// Le diagnostic et l'assistant n'ont pas besoin des mêmes champs.
func TestFormaterFiches_LeDiagnosticEtLAssistantDifferent(t *testing.T) {
	p := []Plant{fichePourTest("Monstera", nil)}

	diag := formaterFiches(p, "fr", true)
	if !strings.Contains(diag, "Nuisibles connus") || !strings.Contains(diag, "Araignées rouges") {
		t.Error("le diagnostic doit recevoir les nuisibles")
	}
	if strings.Contains(diag, "Durée d'ensoleillement") {
		t.Error("le diagnostic n'a que faire de la durée d'ensoleillement")
	}

	chat := formaterFiches(p, "fr", false)
	if !strings.Contains(chat, "Lumière vive indirecte") || !strings.Contains(chat, "Facile") {
		t.Error("l'assistant doit recevoir les soins")
	}
	if strings.Contains(chat, "Signes de manque d'eau") {
		t.Error("l'assistant n'a que faire des signes d'arrosage détaillés")
	}
}

// La toxicité vient des drapeaux structurés, pas du texte. Une abstention y est
// une décision : sans drapeau, on ne dit RIEN plutôt que « non toxique ».
func TestFormaterFiches_LaToxiciteVientDesDrapeaux(t *testing.T) {
	avec := formaterFiches([]Plant{fichePourTest("Monstera",
		&PlantFlags{ToxicToPets: true, ToxicToChildren: true})}, "fr", true)
	if !strings.Contains(avec, "Toxique pour les animaux") || !strings.Contains(avec, "ingestion par un enfant") {
		t.Error("les deux drapeaux posés doivent apparaître")
	}

	sans := formaterFiches([]Plant{fichePourTest("Monstera", nil)}, "fr", true)
	if strings.Contains(sans, "Toxique") || strings.Contains(sans, "toxique") {
		t.Error("sans drapeau, ne rien affirmer — une abstention est une décision (#489)")
	}

	negatif := formaterFiches([]Plant{fichePourTest("Monstera", &PlantFlags{})}, "fr", true)
	if strings.Contains(negatif, "Toxique") {
		t.Error("un drapeau à false ne doit rien produire non plus")
	}
}

// Une fiche sans aucune traduction ne doit pas produire un bloc vide mais
// annoncé : mieux vaut aucun contexte qu'un en-tête sans contenu.
func TestFormaterFiches_AucuneFicheExploitableRendVide(t *testing.T) {
	if out := formaterFiches([]Plant{{Name: "Sans traduction"}}, "fr", true); out != "" {
		t.Errorf("attendu vide, obtenu %q", out)
	}
	if out := formaterFiches(nil, "fr", true); out != "" {
		t.Errorf("attendu vide sur liste nulle, obtenu %q", out)
	}
}

// Le nom de la fiche est repris du document : il doit être assaini comme le
// reste. Ce qui compte n'est pas qu'un « ## » disparaisse — en milieu de ligne
// ce n'en est pas un — mais qu'aucun SAUT DE LIGNE ne subsiste, faute de quoi
// une fiche mal saisie ouvrirait une fausse section dans le bloc de référence.
func TestFormaterFiches_LeNomNePeutPasOuvrirDeFausseSection(t *testing.T) {
	p := fichePourTest("Monstera\ndeliciosa\t## faux titre", nil)
	out := formaterFiches([]Plant{p}, "fr", true)

	if strings.Count(out, "\n## ") != 1 {
		t.Errorf("une seule section attendue, le nom ne doit pas en ouvrir d'autre : %q", out)
	}
	if strings.Contains(out, "Monstera\ndeliciosa") {
		t.Error("le saut de ligne du nom doit être neutralisé")
	}
	if !strings.Contains(out, "Monstera deliciosa") {
		t.Error("le nom doit rester lisible une fois aplati")
	}
}

// Plusieurs fiches produisent plusieurs sections.
func TestFormaterFiches_PlusieursFiches(t *testing.T) {
	out := formaterFiches([]Plant{
		fichePourTest("Monstera", nil),
		fichePourTest("Ficus", nil),
	}, "fr", false)
	if strings.Count(out, "\n## ") != 2 {
		t.Errorf("2 sections attendues : %q", out)
	}
}

// La langue demandée doit être servie quand elle existe.
func TestFormaterFiches_RespecteLaLangue(t *testing.T) {
	out := formaterFiches([]Plant{fichePourTest("Monstera", nil)}, "en", false)
	if !strings.Contains(out, "Bright indirect light") {
		t.Errorf("la traduction anglaise doit être servie : %q", out)
	}
}
