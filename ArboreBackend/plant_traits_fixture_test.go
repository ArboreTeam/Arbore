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
	ID       string            `json:"id"`
	Nom      string            `json:"nom"`
	Pourquoi string            `json:"pourquoi"`
	Profil   *profilFixture    `json:"profil"`
	Flags    map[string]bool   `json:"flags"`
	Prose    map[string]string `json:"prose"`
	Attendu  attenduFixture    `json:"attendu"`
}

type profilFixture struct {
	PetToxicity   *PlantToxicityFact `json:"petToxicity"`
	ChildToxicity *PlantToxicityFact `json:"childToxicity"`
}

type attenduFixture struct {
	VerdictPet   *string           `json:"verdictPet"`
	VerdictChild *string           `json:"verdictChild"`
	Issue        map[string]string `json:"issue"`
	Admis        map[string]bool   `json:"admis"`
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
	var dPet, dChild *bool
	if c.Flags != nil {
		v := c.Flags["toxicToPets"]
		dPet = &v
		w := c.Flags["toxicToChildren"]
		dChild = &w
	}
	return VerdictAvecRepli(fPet, dPet), VerdictAvecRepli(fChild, dChild)
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
	for _, id := range []string{"prose_qui_ment", "nom_qui_ment"} {
		if !vus[id] {
			t.Errorf("cas « %s » absent : rien ne prouve qu'on ne lit plus le texte", id)
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
