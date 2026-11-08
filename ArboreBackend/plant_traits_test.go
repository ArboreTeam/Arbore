package main

import (
	"encoding/json"
	"testing"
)

// Les traits de plante sont des valeurs closes, et non de la prose à relire
// (#792).
//
// Ils se dérivaient de listes de mots-clés appliquées au texte TRADUIT des
// fiches : la même plante sortait `large` en français et `unknown` en allemand,
// un `flowering: false` retombait sur la prose et une description mentionnant
// « fleur » suffisait à la déclarer fleurie, et `contains("hoya")` appariait
// n'importe quelle chaîne contenant ces quatre lettres — ce dernier décidant
// d'une capacité PHYSIQUE de pose.
//
// Ces tests pinnent les deux règles qui remplacent tout ça : le vocabulaire est
// fermé, et ce qu'on ne comprend pas tombe vers le PLANCHER.

func TestTailleAccepteLeVocabulaireFerme(t *testing.T) {
	for _, v := range []string{"small", "medium", "large", "unknown"} {
		if !TailleValide(v) {
			t.Errorf("%q devrait appartenir au vocabulaire", v)
		}
	}
}

func TestTraitTriEtatAccepteSesTroisValeurs(t *testing.T) {
	for _, v := range []string{"yes", "no", "unknown"} {
		if !TraitTriEtatValide(v) {
			t.Errorf("%q devrait appartenir au vocabulaire", v)
		}
	}
}

func TestLesVocabulairesTolerentCasseEtEspaces(t *testing.T) {
	cas := []struct {
		valeur string
		valide func(string) bool
	}{
		{" MEDIUM ", TailleValide},
		{"\tLarge\n", TailleValide},
		{" YES ", TraitTriEtatValide},
		{"No", TraitTriEtatValide},
		{" greenplant ", NaturePlanteValide},
		{"CACTUSSUCCULENT", NaturePlanteValide},
		{" addColor ", ButAmenagementValide},
		{"CREATEPRIVACY", ButAmenagementValide},
		{" White ", CouleurPlanteValide},
		{" CEILING ", PoseValide},
	}
	for _, c := range cas {
		if !c.valide(c.valeur) {
			t.Errorf("%q devrait être accepté après normalisation", c.valeur)
		}
	}
}

// Le vocabulaire des natures est RELEVÉ de `PlantCatalogKind` côté iOS : s'il
// diverge, les deux côtés ne décrivent plus les mêmes plantes. `conifer` y est
// ajouté, parce que la typologie portait le port `conifere` sur 39 fiches sans
// aucune cible.
func TestLeVocabulaireDesNaturesEstCeluiDuClient(t *testing.T) {
	attendues := []string{
		"greenPlant", "floweringPlant", "cactusSucculent", "palm", "fern",
		"orchid", "tree", "shrub", "perennial", "annual", "grass",
		"groundcover", "climbing", "aromaticEdible", "conifer",
	}
	for _, v := range attendues {
		if !NaturePlanteValide(v) {
			t.Errorf("%q devrait appartenir au vocabulaire des natures", v)
		}
	}
	if len(naturesValides) != len(attendues) {
		t.Errorf("le vocabulaire porte %d valeurs, le client en connaît %d : ils ont divergé",
			len(naturesValides), len(attendues))
	}
}

func TestLeVocabulaireDesButsEstCeluiDuClient(t *testing.T) {
	attendus := []string{
		"addColor", "createPrivacy", "addVolume", "coverWall", "createCascade",
		"coverGround", "attractPollinators", "edibleAromatic", "focalPoint",
	}
	for _, v := range attendus {
		if !ButAmenagementValide(v) {
			t.Errorf("%q devrait appartenir au vocabulaire des buts", v)
		}
	}
	if len(butsValides) != len(attendus) {
		t.Errorf("le vocabulaire porte %d buts, le client en connaît %d", len(butsValides), len(attendus))
	}
}

func TestLeVocabulaireDesCouleursEstCeluiDuClient(t *testing.T) {
	attendues := []string{"white", "yellow", "orange", "red", "pink", "purple", "blue", "green", "dark"}
	for _, v := range attendues {
		if !CouleurPlanteValide(v) {
			t.Errorf("%q devrait appartenir au vocabulaire des couleurs", v)
		}
	}
	if len(couleursValides) != len(attendues) {
		t.Errorf("le vocabulaire porte %d couleurs, le client en connaît %d", len(couleursValides), len(attendues))
	}
}

// `variegated` et `flowering` relèvent de l'apparence et du trait, pas de la
// couleur : les ranger ici rendrait « panaché » comparable à « rouge ».
func TestLesCouleursNeContiennentPasLApparence(t *testing.T) {
	for _, v := range []string{"variegated", "flowering"} {
		if CouleurPlanteValide(v) {
			t.Errorf("%q ne devrait PAS être une couleur", v)
		}
	}
}

// Les poses sont celles de `ARPlacementMode`, et rien de plus : ce champ décide
// d'un geste physique, donc une valeur de plus y signifie une pose que l'app ne
// sait pas exécuter.
func TestLesPosesSontCellesDuModeDePlacement(t *testing.T) {
	for _, v := range []string{"floor", "wall", "ceiling"} {
		if !PoseValide(v) {
			t.Errorf("%q devrait être une pose valide", v)
		}
	}
	if len(posesValides) != 3 {
		t.Errorf("le vocabulaire des poses porte %d valeurs, attendu 3", len(posesValides))
	}
	for _, v := range []string{"balcony", "table", "hanging", "suspension", ""} {
		if PoseValide(v) {
			t.Errorf("%q ne devrait PAS être une pose du vocabulaire", v)
		}
	}
}

// La prose qui alimentait l'ancienne dérivation ne doit appartenir à aucun
// vocabulaire. Ces chaînes sont les mots-clés et les fragments de description
// que les listes iOS appariaient.
func TestLesVocabulairesRefusentLaProseQuiLesAlimentait(t *testing.T) {
	refusees := []string{
		"", "   ",
		// « shrub » et « tree » manquent volontairement : ce sont des valeurs du
		// vocabulaire, et c'est bien tout le point — le mot n'était pas faux,
		// c'est le fait de le CHERCHER DANS LA PROSE qui l'était.
		"arbuste", "palmier", "strauch", "mini ",
		"floraison", "fleuri", "fleur",
		"grimpant", "grimpante", "lierre", "pothos", "hoya", "rhipsalis",
		"couvre-sol", "mousse", "tuteur mousse",
		"true", "false", "yes/no", "maybe",
		"petite plante compacte pour petits espaces",
	}
	for _, v := range refusees {
		if TailleValide(v) {
			t.Errorf("%q ne devrait PAS être une taille", v)
		}
		if TraitTriEtatValide(v) {
			t.Errorf("%q ne devrait PAS être un trait tri-état", v)
		}
		if NaturePlanteValide(v) {
			t.Errorf("%q ne devrait PAS être une nature", v)
		}
		if ButAmenagementValide(v) {
			t.Errorf("%q ne devrait PAS être un but", v)
		}
		if PoseValide(v) {
			t.Errorf("%q ne devrait PAS être une pose", v)
		}
	}
}

// LE SENS DE LA CHUTE. Une valeur qu'on ne comprend pas ne doit jamais devenir
// une valeur affirmative : elle doit coûter une suggestion perdue, pas un geste
// impossible ni une plante déclarée facile qui ne l'est pas.
func TestLaLectureTombeVersLePlancher(t *testing.T) {
	horsVocabulaire := []string{"enorme", "XL", "tres grande", "maybe", "true", "oui", ""}
	for _, v := range horsVocabulaire {
		if got := TailleDepuisFait(&PlantTraitFact{Value: v}); got != "unknown" {
			t.Errorf("taille %q lue %q, attendu unknown", v, got)
		}
		if got := TraitDepuisFait(&PlantTraitFact{Value: v}); got != "unknown" {
			t.Errorf("trait %q lu %q, attendu unknown", v, got)
		}
	}
	if got := TailleDepuisFait(nil); got != "unknown" {
		t.Errorf("taille absente lue %q, attendu unknown", got)
	}
	if got := TraitDepuisFait(nil); got != "unknown" {
		t.Errorf("trait absent lu %q, attendu unknown", got)
	}
}

// Le plancher d'un trait tri-état est `unknown` et NON `no` : rendre `no`
// transformerait notre silence en une affirmation sur la plante, ce qui est
// exactement ce que faisaient les booléens.
func TestLePlancherDUnTraitNEstPasUneNegation(t *testing.T) {
	for _, f := range []*PlantTraitFact{nil, {Value: ""}, {Value: "pas vraiment"}} {
		if got := TraitDepuisFait(f); got == "no" {
			t.Errorf("un trait non lisible rend %q : le silence devient une négation", got)
		}
	}
	// Et un `no` STOCKÉ est bien une affirmation, qui doit survivre à la lecture.
	if got := TraitDepuisFait(&PlantTraitFact{Value: "no"}); got != "no" {
		t.Errorf("un `no` stocké est lu %q : l'affirmation est perdue", got)
	}
}

func TestLaLectureRendLaFormeCanonique(t *testing.T) {
	liste := NaturesDepuisFait(&PlantStringListFact{Value: []string{"GREENPLANT", " cactussucculent ", "AromaticEdible"}})
	attendu := []string{"greenPlant", "cactusSucculent", "aromaticEdible"}
	if len(liste.Valeurs) != len(attendu) {
		t.Fatalf("natures lues %v, attendu %v", liste.Valeurs, attendu)
	}
	for i := range attendu {
		if liste.Valeurs[i] != attendu[i] {
			t.Errorf("nature %d = %q, attendu %q (la casse stockée ne doit pas fuir)", i, liste.Valeurs[i], attendu[i])
		}
	}
}

// LA DISTINCTION QUI N'EXISTE DANS AUCUNE LISTE : vide et absente.
func TestUneListeVideNEstPasUneListeAbsente(t *testing.T) {
	absente := NaturesDepuisFait(nil)
	if absente.Renseignee {
		t.Error("une liste absente se déclare renseignée : le silence devient une affirmation")
	}
	if absente.EstVideAffirmee() {
		t.Error("une liste absente passe pour une liste vide affirmée")
	}

	vide := NaturesDepuisFait(&PlantStringListFact{Value: []string{}})
	if !vide.Renseignee {
		t.Error("une liste présente et vide se déclare non renseignée : l'affirmation est perdue")
	}
	if !vide.EstVideAffirmee() {
		t.Error("une liste présente et vide devrait être une vacuité AFFIRMÉE")
	}
	if len(vide.Valeurs) != 0 {
		t.Errorf("une liste vide rend %v", vide.Valeurs)
	}
}

// Une valeur hors vocabulaire est ÉCARTÉE et conservée en clair, et surtout
// elle n'emporte pas la fiche : le profil se migre par morceaux, et une clé
// qu'on ne comprend pas encore ne doit pas faire disparaître le soleil, la
// température et les dimensions avec elle.
func TestUneValeurHorsVocabulaireEstEcarteeEtNonDevinee(t *testing.T) {
	liste := NaturesDepuisFait(&PlantStringListFact{Value: []string{"shrub", "bonsai", "tree"}})
	if !liste.Renseignee {
		t.Error("la liste existe pourtant")
	}
	if !memesValeurs(liste.Valeurs, []string{"shrub", "tree"}) {
		t.Errorf("valeurs retenues %v, attendu [shrub tree]", liste.Valeurs)
	}
	if !memesValeurs(liste.Rejetees, []string{"bonsai"}) {
		t.Errorf("valeurs rejetées %v, attendu [bonsai]", liste.Rejetees)
	}
	// Une liste dont TOUT est hors vocabulaire ne doit pas se lire comme une
	// vacuité affirmée : c'est une perte, et elle doit rester visible.
	perdue := PosesDepuisFait(&PlantStringListFact{Value: []string{"balcony"}})
	if perdue.EstVideAffirmee() {
		t.Error("une liste intégralement rejetée passe pour une vacuité affirmée")
	}
}

func TestLaLectureDedoublonneEtGardeLOrdre(t *testing.T) {
	liste := ButsDepuisFait(&PlantStringListFact{Value: []string{"focalPoint", "addColor", "FOCALPOINT", "addColor"}})
	if !memesValeurs(liste.Valeurs, []string{"focalPoint", "addColor"}) {
		t.Errorf("buts lus %v, attendu [focalPoint addColor]", liste.Valeurs)
	}
}

// Le repli par drapeau, transposé mot pour mot de la toxicité.
func TestLeRepliParDrapeauNInformeQueParSonVrai(t *testing.T) {
	vrai, faux := true, false

	if got := TraitAvecRepli(nil, &vrai); got != "yes" {
		t.Errorf("fait absent + drapeau levé = %q, attendu yes", got)
	}
	// Son `false` a voulu dire à la fois « la source dit non » et « personne
	// n'a regardé » : il ne vaut donc PAS une négation démontrée.
	if got := TraitAvecRepli(nil, &faux); got != "unknown" {
		t.Errorf("fait absent + drapeau baissé = %q, attendu unknown — un drapeau baissé ne prouve rien", got)
	}
	if got := TraitAvecRepli(nil, nil); got != "unknown" {
		t.Errorf("ni fait ni drapeau = %q, attendu unknown", got)
	}
}

// LE DÉFAUT QUE LE CORRECTIF DE LA TOXICITÉ VIENT DE PAYER, transposé : un fait
// qui dit `unknown` n'autorise PAS à consulter le drapeau. Il dit « on a
// regardé sans conclure », et le recouvrir d'un drapeau levé transformerait une
// absence mesurée en affirmation — 199 axes et 108 plantes masquées à tort sur
// l'axe toxicité.
func TestUnFaitPresentFaitAutoriteMemeQuandIlDitInconnu(t *testing.T) {
	vrai := true
	if got := TraitAvecRepli(&PlantTraitFact{Value: "unknown"}, &vrai); got != "unknown" {
		t.Errorf("fait `unknown` + drapeau levé = %q : l'absence mesurée a été recouverte", got)
	}
	if got := TraitAvecRepli(&PlantTraitFact{Value: "no"}, &vrai); got != "no" {
		t.Errorf("fait `no` + drapeau levé = %q : le fait stocké doit primer", got)
	}
	if got := TraitAvecRepli(&PlantTraitFact{Value: "yes"}, &vrai); got != "yes" {
		t.Errorf("fait `yes` = %q", got)
	}
	// Une valeur hors vocabulaire est un fait PRÉSENT : elle tombe vers le
	// plancher et n'ouvre pas la porte au drapeau, sinon un typo dans la base
	// ferait remonter une affirmation héritée.
	if got := TraitAvecRepli(&PlantTraitFact{Value: "maybe"}, &vrai); got != "unknown" {
		t.Errorf("fait hors vocabulaire + drapeau levé = %q, attendu unknown", got)
	}
}

// ---------- ÉCRITURE : ON REFUSE, ON NE CORRIGE PAS ----------

func TestLEcritureAccepteUnProfilDeTraitsValide(t *testing.T) {
	p := &PlantBotanicalProfile{
		Size:      &PlantTraitFact{Value: "medium"},
		Kinds:     &PlantStringListFact{Value: []string{"greenPlant", "climbing"}},
		Goals:     &PlantStringListFact{Value: []string{"addVolume"}},
		Colors:    &PlantStringListFact{Value: []string{"green"}},
		Placement: &PlantStringListFact{Value: []string{"floor", "wall"}},
		Flowering: &PlantTraitFact{Value: "no"},
		EasyCare:  &PlantTraitFact{Value: "unknown"},
	}
	if fautes := ValiderTraitsDuProfil(p); len(fautes) > 0 {
		t.Errorf("profil valide refusé : %v", fautes)
	}
	// Un profil absent et un profil sans traits sont écrivables : ne pas
	// remplir reste permis, mal remplir ne l'est pas.
	if fautes := ValiderTraitsDuProfil(nil); len(fautes) > 0 {
		t.Errorf("profil absent refusé : %v", fautes)
	}
	if fautes := ValiderTraitsDuProfil(&PlantBotanicalProfile{}); len(fautes) > 0 {
		t.Errorf("profil sans traits refusé : %v", fautes)
	}
	// Un champ présent mais vide est une absence, pas une faute.
	if fautes := ValiderTraitsDuProfil(&PlantBotanicalProfile{Size: &PlantTraitFact{Value: ""}}); len(fautes) > 0 {
		t.Errorf("champ vide refusé : %v", fautes)
	}
}

func TestLEcritureRefuseToutesLesValeursHorsVocabulaire(t *testing.T) {
	p := &PlantBotanicalProfile{
		Size:      &PlantTraitFact{Value: "enorme"},
		Flowering: &PlantTraitFact{Value: "maybe"},
		Kinds:     &PlantStringListFact{Value: []string{"shrub", "bonsai"}},
		Placement: &PlantStringListFact{Value: []string{"balcony"}},
	}
	fautes := ValiderTraitsDuProfil(p)
	if len(fautes) != 4 {
		t.Fatalf("%d fautes rendues, attendu 4 : %v — un écrivain corrigé un champ à la fois reposte autant de fois qu'il a de fautes", len(fautes), fautes)
	}
	parChamp := map[string]string{}
	for _, f := range fautes {
		parChamp[f.Champ] = f.Valeur
	}
	for champ, valeur := range map[string]string{
		"size": "enorme", "flowering": "maybe", "kinds": "bonsai", "placement": "balcony",
	} {
		if parChamp[champ] != valeur {
			t.Errorf("faute sur %q = %q, attendu %q (le refus doit nommer la valeur)", champ, parChamp[champ], valeur)
		}
	}
}

// Le périmètre de la validation d'écriture est un CHOIX : la toxicité, la
// fiabilité et le reste du profil n'y sont pas, parce que des fiches réelles
// portent encore des valeurs de provenance héritées (`unresolved`) et que
// refuser leur réécriture bloquerait la migration qui doit les corriger.
func TestLEcritureNeValidePasEncoreLeResteDuProfil(t *testing.T) {
	p := &PlantBotanicalProfile{
		PetToxicity: &PlantToxicityFact{
			Value:    "unknown",
			Evidence: &PlantDataEvidence{Reliability: "unresolved"},
		},
	}
	if fautes := ValiderTraitsDuProfil(p); len(fautes) > 0 {
		t.Errorf("la validation déborde sur le reste du profil : %v", fautes)
	}
}

// ---------- SCHÉMA ----------

func TestLesTraitsFontUnAllerRetourJSONSansPerte(t *testing.T) {
	version := VersionSchemaBotanique
	plant := Plant{
		Name: "Chlorophytum comosum",
		BotanicalProfile: &PlantBotanicalProfile{
			Size: &PlantTraitFact{
				Value: "small",
				Evidence: &PlantDataEvidence{
					SourceName:  "typologie du catalogue",
					ReviewedAt:  "2026-11-08",
					Reliability: "moderate",
				},
			},
			Kinds:         &PlantStringListFact{Value: []string{"greenPlant"}},
			Goals:         &PlantStringListFact{Value: []string{"createCascade"}},
			Colors:        &PlantStringListFact{Value: []string{"green", "white"}},
			Placement:     &PlantStringListFact{Value: []string{"floor", "ceiling"}},
			Trailing:      &PlantTraitFact{Value: "yes"},
			Flowering:     &PlantTraitFact{Value: "no"},
			SchemaVersion: &version,
		},
	}

	data, err := json.Marshal(plant)
	if err != nil {
		t.Fatalf("marshal plant: %v", err)
	}
	var decoded Plant
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal plant: %v", err)
	}
	p := decoded.BotanicalProfile
	if p == nil {
		t.Fatal("le profil a été perdu")
	}
	if got := TailleDepuisFait(p.Size); got != "small" {
		t.Errorf("size = %q", got)
	}
	if got := p.Size.Evidence.SourceName; got != "typologie du catalogue" {
		t.Errorf("la provenance de la taille est perdue : %q", got)
	}
	if got := TraitDepuisFait(p.Trailing); got != "yes" {
		t.Errorf("trailing = %q", got)
	}
	if got := TraitDepuisFait(p.Flowering); got != "no" {
		t.Errorf("flowering = %q", got)
	}
	if got := PosesDepuisFait(p.Placement); !memesValeurs(got.Valeurs, []string{"floor", "ceiling"}) {
		t.Errorf("placement = %v", got.Valeurs)
	}
	if p.SchemaVersion == nil || *p.SchemaVersion != VersionSchemaBotanique {
		t.Errorf("schemaVersion = %v, attendu %d", p.SchemaVersion, VersionSchemaBotanique)
	}
}

// Un champ de trait absent ne doit pas apparaître dans le document : une clé
// présente à `null` se lit comme une donnée, et la base en porterait douze par
// fiche non auditée.
func TestLesTraitsAbsentsNeSontPasSerialises(t *testing.T) {
	data, err := json.Marshal(&PlantBotanicalProfile{})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if string(data) != "{}" {
		t.Errorf("un profil vide se sérialise en %s, attendu {}", data)
	}
}

// La version du schéma a changé de forme avec #792, donc elle s'incrémente :
// un lecteur doit pouvoir SAVOIR qu'il lit la forme antérieure aux traits.
func TestLaVersionDuSchemaAEteIncrementee(t *testing.T) {
	if VersionSchemaBotanique <= 1 {
		t.Errorf("VersionSchemaBotanique = %d : le profil a gagné des champs sans le dire", VersionSchemaBotanique)
	}
}
