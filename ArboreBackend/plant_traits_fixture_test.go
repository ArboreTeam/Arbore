package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// Les cas de référence partagés avec iOS (#792).
//
// `fixtures/plant-traits.json` est lu ici ET par `PlantTraitsFixtureTests.swift`.
// C'est ce fichier, et non la discipline, qui empêche les deux implémentations
// de s'écarter : si l'une change d'avis sur un cas, son test tombe.
//
// Le chemin est relatif au dépôt plutôt que copié dans `testdata/` : une copie
// diverge, et c'est précisément ce qu'on cherche à rendre impossible.

type casFixture struct {
	ID       string                 `json:"id"`
	Nom      string                 `json:"nom"`
	Pourquoi string                 `json:"pourquoi"`
	Profil   *PlantBotanicalProfile `json:"profil"`
	Flags    map[string]bool        `json:"flags"`
	Prose    map[string]string      `json:"prose"`
	Attendu  attenduFixture         `json:"attendu"`
}

// `profil` se décode dans le VRAI type du schéma, et non dans un sous-ensemble
// écrit pour le test : la fixture prouve au passage qu'elle est une fiche
// valide, et un champ qu'on ajouterait au schéma sans l'ajouter ici ne pourrait
// pas passer inaperçu.

type attenduFixture struct {
	VerdictPet   *string           `json:"verdictPet"`
	VerdictChild *string           `json:"verdictChild"`
	Issue        map[string]string `json:"issue"`
	Admis        map[string]bool   `json:"admis"`
	// Traits : la valeur LUE attendue pour chaque trait que le cas affirme.
	// Une clé absente n'est pas affirmée — un cas n'a pas à se prononcer sur
	// les douze champs pour se prononcer sur un seul.
	Traits *traitsAttendus `json:"traits"`
	// EcritureRefusee : la fiche doit être REFUSÉE à l'écriture. La lecture est
	// indulgente, l'écriture ne l'est pas, et les deux sont affirmées depuis le
	// même fichier parce qu'elles ne se ressemblent pas.
	EcritureRefusee bool `json:"ecritureRefusee"`
}

// traitsAttendus : des pointeurs, pour distinguer « la valeur attendue est
// `unknown` » de « ce cas ne se prononce pas ». Sans eux, le zéro de Go
// transformerait chaque silence du cas en assertion.
type traitsAttendus struct {
	Size           *string `json:"size"`
	Flowering      *string `json:"flowering"`
	EasyCare       *string `json:"easyCare"`
	Compact        *string `json:"compact"`
	Climbing       *string `json:"climbing"`
	Trailing       *string `json:"trailing"`
	HumidityLoving *string `json:"humidityLoving"`
	AirPurifying   *string `json:"airPurifying"`

	Kinds     *listeAttendue `json:"kinds"`
	Goals     *listeAttendue `json:"goals"`
	Colors    *listeAttendue `json:"colors"`
	Placement *listeAttendue `json:"placement"`
}

// listeAttendue porte `renseignee` parce qu'une liste vide et une liste absente
// ne disent pas la même chose, et qu'aucune liste JSON ne les distingue.
type listeAttendue struct {
	Renseignee bool     `json:"renseignee"`
	Valeurs    []string `json:"valeurs"`
	Rejetees   []string `json:"rejetees"`
}

type fixturePartagee struct {
	Contraintes []string     `json:"contraintes"`
	Plantes     []casFixture `json:"plantes"`
}

func chargerFixture(t *testing.T) fixturePartagee {
	t.Helper()
	chemin := filepath.Join("..", "fixtures", "plant-traits.json")
	brut, err := os.ReadFile(chemin)
	if err != nil {
		t.Skipf("fixture partagée introuvable (%v) — le test n'a de sens qu'avec elle", err)
	}
	var f fixturePartagee
	if err := json.Unmarshal(brut, &f); err != nil {
		t.Fatalf("fixture illisible : %v", err)
	}
	if len(f.Plantes) == 0 {
		t.Fatal("fixture vide")
	}
	return f
}

// verdictsDuCas applique le repli par drapeau exactement comme le client.
func verdictsDuCas(c casFixture) (animaux, enfants VerdictToxicite) {
	var fPet, fChild *PlantToxicityFact
	if c.Profil != nil {
		fPet, fChild = c.Profil.PetToxicity, c.Profil.ChildToxicity
	}
	return VerdictAvecRepli(fPet, drapeauDuCas(c.Flags, "toxicToPets")),
		VerdictAvecRepli(fChild, drapeauDuCas(c.Flags, "toxicToChildren"))
}

func exigenceDe(nom string) ExigenceFoyer {
	switch nom {
	case "animaux":
		return ExigenceFoyer{Animaux: true}
	case "enfants":
		return ExigenceFoyer{Enfants: true}
	case "les_deux":
		return ExigenceFoyer{Animaux: true, Enfants: true}
	default:
		return ExigenceFoyer{}
	}
}

func issueDe(nom string) IssueSurete {
	switch nom {
	case "conflict":
		return SureteEnConflit
	case "undetermined":
		return SureteNonEtablie
	default:
		return SureteSatisfaite
	}
}

// nomVerdict traduit vers le vocabulaire STOCKÉ, celui que la fixture affirme.
// `nil` y signifie non établi, et jamais « sûre ».
func nomVerdict(v VerdictToxicite, f *PlantToxicityFact) *string {
	if v == ToxiciteNonEtablie {
		return nil
	}
	s := "safe"
	if v == ToxiciteAvertit {
		s = "toxic"
	}
	return &s
}

func memeVerdict(a, b *string) bool {
	switch {
	case a == nil && b == nil:
		return true
	case a == nil || b == nil:
		return false
	default:
		// La fixture écrit la valeur STOCKÉE (`irritant`), le verdict rendu au
		// lecteur la confond avec `toxic` : c'est le contrat, pas un écart.
		av, bv := *a, *b
		if av == "irritant" {
			av = "toxic"
		}
		if bv == "irritant" {
			bv = "toxic"
		}
		return av == bv
	}
}

func TestFixtureChaqueCasDitCeQuIlProuve(t *testing.T) {
	for _, c := range chargerFixture(t).Plantes {
		if c.Pourquoi == "" {
			t.Errorf("le cas « %s » ne dit pas ce qu'il protège", c.ID)
		}
	}
}

func TestFixtureLesGardesAntiRegressionSontPresentes(t *testing.T) {
	vus := map[string]bool{}
	for _, c := range chargerFixture(t).Plantes {
		vus[c.ID] = true
	}
	for _, id := range []string{"prose_qui_ment", "nom_qui_ment", "prose_qui_ment_sur_les_traits", "lierre_dans_la_prose"} {
		if !vus[id] {
			t.Errorf("cas « %s » absent : rien ne prouve qu'on ne lit plus le texte", id)
		}
	}
}

// drapeauDuCas rend le drapeau nommé, ou nil s'il est ABSENT du document.
//
// La distinction compte : un drapeau absent n'est pas un drapeau baissé. Rendre
// `false` pour une clé qui n'existe pas reviendrait à affirmer à la place de la
// fiche, et c'est tout ce que cette issue retire.
func drapeauDuCas(flags map[string]bool, nom string) *bool {
	if flags == nil {
		return nil
	}
	v, ok := flags[nom]
	if !ok {
		return nil
	}
	return &v
}

// La prose d'accompagnement d'un trait est conservée et n'est JAMAIS lue pour
// décider : le cas `floraison_niee` porte « Feuillage decoratif » en `detail`
// et son verdict stocké dit `no`. Si un jour le `detail` pesait sur la lecture,
// le parsing serait revenu par la petite porte.
func TestFixtureLaProseDAccompagnementNeDecideDeRien(t *testing.T) {
	trouve := false
	for _, c := range chargerFixture(t).Plantes {
		if c.Profil == nil || c.Profil.Flowering == nil || c.Profil.Flowering.Detail == "" {
			continue
		}
		trouve = true
		avec := TraitDepuisFait(c.Profil.Flowering)
		sans := TraitDepuisFait(&PlantTraitFact{Value: c.Profil.Flowering.Value})
		if avec != sans {
			t.Errorf("%s · flowering : %q avec le detail, %q sans — le detail a pesé (%s)",
				c.ID, avec, sans, c.Pourquoi)
		}
	}
	if !trouve {
		t.Error("aucun cas ne porte de prose d'accompagnement : rien ne prouve qu'elle ne décide pas")
	}
}

func TestFixtureLesTraitsScalairesLusSontCeuxAffirmes(t *testing.T) {
	for _, c := range chargerFixture(t).Plantes {
		attendus := c.Attendu.Traits
		if attendus == nil {
			continue
		}
		var p PlantBotanicalProfile
		if c.Profil != nil {
			p = *c.Profil
		}

		// La taille se lit du seul fait : aucun drapeau ne dit une taille.
		if attendus.Size != nil {
			if got := TailleDepuisFait(p.Size); got != *attendus.Size {
				t.Errorf("%s · size : %q, attendu %q (%s)", c.ID, got, *attendus.Size, c.Pourquoi)
			}
		}

		triEtats := []struct {
			nom     string
			fait    *PlantTraitFact
			attendu *string
		}{
			{"flowering", p.Flowering, attendus.Flowering},
			{"easyCare", p.EasyCare, attendus.EasyCare},
			{"compact", p.Compact, attendus.Compact},
			{"climbing", p.Climbing, attendus.Climbing},
			{"trailing", p.Trailing, attendus.Trailing},
			{"humidityLoving", p.HumidityLoving, attendus.HumidityLoving},
			{"airPurifying", p.AirPurifying, attendus.AirPurifying},
		}
		for _, tr := range triEtats {
			if tr.attendu == nil {
				continue
			}
			got := TraitAvecRepli(tr.fait, drapeauDuCas(c.Flags, tr.nom))
			if got != *tr.attendu {
				t.Errorf("%s · %s : %q, attendu %q (%s)", c.ID, tr.nom, got, *tr.attendu, c.Pourquoi)
			}
		}
	}
}

func TestFixtureLesTraitsEnListeLusSontCeuxAffirmes(t *testing.T) {
	for _, c := range chargerFixture(t).Plantes {
		attendus := c.Attendu.Traits
		if attendus == nil {
			continue
		}
		var p PlantBotanicalProfile
		if c.Profil != nil {
			p = *c.Profil
		}
		listes := []struct {
			nom     string
			lue     ListeFermee
			attendu *listeAttendue
		}{
			{"kinds", NaturesDepuisFait(p.Kinds), attendus.Kinds},
			{"goals", ButsDepuisFait(p.Goals), attendus.Goals},
			{"colors", CouleursDepuisFait(p.Colors), attendus.Colors},
			{"placement", PosesDepuisFait(p.Placement), attendus.Placement},
		}
		for _, l := range listes {
			if l.attendu == nil {
				continue
			}
			if l.lue.Renseignee != l.attendu.Renseignee {
				t.Errorf("%s · %s : renseignee=%v, attendu %v (%s)",
					c.ID, l.nom, l.lue.Renseignee, l.attendu.Renseignee, c.Pourquoi)
			}
			if !memesValeurs(l.lue.Valeurs, l.attendu.Valeurs) {
				t.Errorf("%s · %s : %v, attendu %v (%s)",
					c.ID, l.nom, l.lue.Valeurs, l.attendu.Valeurs, c.Pourquoi)
			}
			if !memesValeurs(l.lue.Rejetees, l.attendu.Rejetees) {
				t.Errorf("%s · %s : rejetees %v, attendu %v (%s)",
					c.ID, l.nom, l.lue.Rejetees, l.attendu.Rejetees, c.Pourquoi)
			}
		}
	}
}

// memesValeurs compare dans l'ORDRE : l'ordre d'origine du vocabulaire est
// conservé par la lecture, et une liste réordonnée se verrait ici.
func memesValeurs(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// L'écriture refuse là où la lecture écarte, et le même fichier affirme les
// deux. Le test est bilatéral : une fiche qui ne déclare pas de refus ne doit
// pas en déclencher, sinon la validation s'étendrait sans que personne le voie.
func TestFixtureLEcritureEstRefuseeExactementOuCestAffirme(t *testing.T) {
	for _, c := range chargerFixture(t).Plantes {
		fautes := ValiderTraitsDuProfil(c.Profil)
		refusee := len(fautes) > 0
		if refusee != c.Attendu.EcritureRefusee {
			t.Errorf("%s : refus à l'écriture = %v (%v), attendu %v (%s)",
				c.ID, refusee, fautes, c.Attendu.EcritureRefusee, c.Pourquoi)
		}
	}
}

// Les démonstrations que l'issue #792 exige du fichier, vérifiées sur le
// fichier lui-même : un cas qu'on retirerait par mégarde ferait tomber ce test
// plutôt que de laisser un trou silencieux dans la couverture.
func TestFixtureCouvreLesDemonstrationsExigees(t *testing.T) {
	var traitInconnu, traitNie, listeVideAffirmee, listeAbsente, horsVocabulaire bool
	for _, c := range chargerFixture(t).Plantes {
		a := c.Attendu.Traits
		if a == nil {
			continue
		}
		for _, v := range []*string{a.Size, a.Flowering, a.EasyCare, a.Compact, a.Climbing, a.Trailing, a.HumidityLoving, a.AirPurifying} {
			if v == nil {
				continue
			}
			if *v == "unknown" {
				traitInconnu = true
			}
			if *v == "no" {
				traitNie = true
			}
		}
		for _, l := range []*listeAttendue{a.Kinds, a.Goals, a.Colors, a.Placement} {
			if l == nil {
				continue
			}
			if !l.Renseignee {
				listeAbsente = true
			}
			if l.Renseignee && len(l.Valeurs) == 0 && len(l.Rejetees) == 0 {
				listeVideAffirmee = true
			}
			if len(l.Rejetees) > 0 {
				horsVocabulaire = true
			}
		}
		if c.Attendu.EcritureRefusee {
			horsVocabulaire = true
		}
	}

	exigences := map[string]bool{
		"un trait `unknown`":                      traitInconnu,
		"un `no` explicite":                       traitNie,
		"une liste VIDE affirmée":                 listeVideAffirmee,
		"une liste ABSENTE, distincte de la vide": listeAbsente,
		"une valeur hors vocabulaire":             horsVocabulaire,
	}
	for quoi, couvert := range exigences {
		if !couvert {
			t.Errorf("le fichier de cas ne porte plus %s : la démonstration manque", quoi)
		}
	}
}

func TestFixtureLesVerdictsSontCeuxAffirmes(t *testing.T) {
	for _, c := range chargerFixture(t).Plantes {
		animaux, enfants := verdictsDuCas(c)
		var fPet, fChild *PlantToxicityFact
		if c.Profil != nil {
			fPet, fChild = c.Profil.PetToxicity, c.Profil.ChildToxicity
		}
		if got := nomVerdict(animaux, fPet); !memeVerdict(got, c.Attendu.VerdictPet) {
			t.Errorf("%s — axe animal : %v, attendu %v (%s)", c.ID, deref(got), deref(c.Attendu.VerdictPet), c.Pourquoi)
		}
		if got := nomVerdict(enfants, fChild); !memeVerdict(got, c.Attendu.VerdictChild) {
			t.Errorf("%s — axe enfant : %v, attendu %v (%s)", c.ID, deref(got), deref(c.Attendu.VerdictChild), c.Pourquoi)
		}
	}
}

func TestFixtureLePredicatRendCeQuiEstAffirme(t *testing.T) {
	f := chargerFixture(t)
	for _, c := range f.Plantes {
		animaux, enfants := verdictsDuCas(c)
		for _, contrainte := range f.Contraintes {
			attendu, ok := c.Attendu.Issue[contrainte]
			if !ok {
				t.Errorf("le cas « %s » ne couvre pas la contrainte « %s »", c.ID, contrainte)
				continue
			}
			got := IssueDeSurete(animaux, enfants, exigenceDe(contrainte))
			if got != issueDe(attendu) {
				t.Errorf("%s sous « %s » : %v, attendu %s (%s)", c.ID, contrainte, got, attendu, c.Pourquoi)
			}
		}
	}
}

func TestFixtureLesPolitiquesAdmettentCeQuiEstAffirme(t *testing.T) {
	for _, c := range chargerFixture(t).Plantes {
		animaux, enfants := verdictsDuCas(c)
		for cle, attendu := range c.Attendu.Admis {
			politique := Parcourable
			contrainte := cle
			if len(cle) > len("offerable_") && cle[:len("offerable_")] == "offerable_" {
				politique, contrainte = Proposable, cle[len("offerable_"):]
			} else if len(cle) > len("browsable_") && cle[:len("browsable_")] == "browsable_" {
				contrainte = cle[len("browsable_"):]
			} else {
				continue
			}
			got := politique.Admet(IssueDeSurete(animaux, enfants, exigenceDe(contrainte)))
			if got != attendu {
				t.Errorf("%s · %s : %v, attendu %v (%s)", c.ID, cle, got, attendu, c.Pourquoi)
			}
		}
	}
}

// La propriété de sûreté, affirmée directement et non déduite de la fixture :
// ce test tomberait même si la fixture se trompait.
func TestAucunePlanteNonSureNEstJamaisProposee(t *testing.T) {
	for _, c := range chargerFixture(t).Plantes {
		animaux, enfants := verdictsDuCas(c)
		for _, contrainte := range []string{"animaux", "enfants", "les_deux"} {
			e := exigenceDe(contrainte)
			sure := true
			if e.Animaux && animaux != ToxiciteSure {
				sure = false
			}
			if e.Enfants && enfants != ToxiciteSure {
				sure = false
			}
			if sure {
				continue
			}
			if Proposable.Admet(IssueDeSurete(animaux, enfants, e)) {
				t.Errorf("%s est PROPOSÉE sous « %s » alors que son verdict ne le permet pas", c.ID, contrainte)
			}
		}
	}
}

func TestToutCeQuiEstProposableEstParcourable(t *testing.T) {
	f := chargerFixture(t)
	for _, c := range f.Plantes {
		animaux, enfants := verdictsDuCas(c)
		for _, contrainte := range f.Contraintes {
			i := IssueDeSurete(animaux, enfants, exigenceDe(contrainte))
			if Proposable.Admet(i) && !Parcourable.Admet(i) {
				t.Errorf("%s est proposable mais pas parcourable sous « %s »", c.ID, contrainte)
			}
		}
	}
}

func TestSansContrainteAucunePlanteNEstEcartee(t *testing.T) {
	for _, c := range chargerFixture(t).Plantes {
		animaux, enfants := verdictsDuCas(c)
		i := IssueDeSurete(animaux, enfants, ExigenceFoyer{})
		if !Parcourable.Admet(i) || !Proposable.Admet(i) {
			t.Errorf("%s est écartée alors que l'utilisateur n'a rien demandé", c.ID)
		}
	}
}

// Les valeurs de la fixture appartiennent au vocabulaire fermé — sauf le cas
// qui existe justement pour prouver qu'une valeur hors vocabulaire tombe vers
// le plancher.
func TestLesValeursDeLaFixtureSontDuVocabulaireSaufLeCasPrevu(t *testing.T) {
	for _, c := range chargerFixture(t).Plantes {
		if c.Profil == nil {
			continue
		}
		for axe, f := range map[string]*PlantToxicityFact{
			"petToxicity": c.Profil.PetToxicity, "childToxicity": c.Profil.ChildToxicity,
		} {
			if f == nil || f.Value == "" {
				continue
			}
			valide := VerdictToxiciteValide(f.Value)
			attenduInvalide := c.ID == "valeur_inconnue_du_vocabulaire"
			if valide == attenduInvalide {
				t.Errorf("%s.%s = %q : valide=%v, or ce cas attend l'inverse", c.ID, axe, f.Value, valide)
			}
		}
	}
}

func deref(s *string) string {
	if s == nil {
		return "<non établi>"
	}
	return *s
}
