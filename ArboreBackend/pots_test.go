package main

import (
	"encoding/json"
	"math"
	"testing"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// pots_test — issues #609 (étape 6), #623, #280.
//
// Deux familles de défauts, de gravités très différentes.
//
// Ne servir aucun pot **dégrade** : la plante recoupée s'affiche nue, c'est
// laid mais visible et réversible. Servir un pot mal posé **trompe** : il
// traverse la plante ou flotte, et l'utilisateur croit à un bug d'AR. Ces tests
// insistent donc sur les cas où l'on doit REFUSER de servir un pot.
//
// Le troisième risque est la régression silencieuse : une plante historique,
// dont le maillage contient déjà son pot, ne doit rien voir changer.

func potDeTest(nom string, rebord float64, defaut bool) Pot {
	return Pot{
		ID:        primitive.NewObjectID(),
		Name:      nom,
		ModelURL:  nom + ".usdz",
		RimRadius: rebord,
		Height:    0.1,
		Default:   defaut,
	}
}

func planteRecoupee(base *PotBase) Plant {
	vrai := true
	return Plant{Name: "Aglaonema Mix", Potless: &vrai, PotBase: base}
}

// socle relevé par l'atelier sur Aglaonema_Mix, en unités du modèle.
func socleReel() *PotBase {
	return &PotBase{X: 0.00432, Y: -0.10521, Z: -0.07449, Radius: 0.16146,
		GroundY: -0.19691, PlantHeight: 0.64856}
}

// --- Échelle ---------------------------------------------------------------

func TestEchellePot_ValeursRelevees(t *testing.T) {
	// Le pot de la bibliothèque a un rebord de 0,058654 ; le socle, 0,16146.
	pot := potDeTest("cachepot_pieds", 0.058654, true)
	got, ok := echellePot(socleReel(), &pot)
	if !ok {
		t.Fatal("la pose devrait être calculable sur des valeurs relevées")
	}
	if want := 0.16146 / 0.058654; math.Abs(got-want) > 1e-9 {
		t.Fatalf("échelle = %v, attendu %v", got, want)
	}
}

func TestEchellePot_RefuseCeQuiNaPasDeSens(t *testing.T) {
	pot := potDeTest("normal", 0.05, true)
	plat := potDeTest("rebord nul", 0, true)
	negatif := potDeTest("rebord négatif", -0.05, true)

	cas := map[string]struct {
		base *PotBase
		pot  *Pot
	}{
		"socle absent":       {nil, &pot},
		"pot absent":         {socleReel(), nil},
		"rebord nul":         {socleReel(), &plat},
		"rebord négatif":     {socleReel(), &negatif},
		"socle de rayon nul": {&PotBase{Radius: 0}, &pot},
		"socle de rayon < 0": {&PotBase{Radius: -1}, &pot},
		"les deux manquants": {nil, nil},
	}
	for nom, c := range cas {
		if _, ok := echellePot(c.base, c.pot); ok {
			t.Errorf("%s : la pose ne devrait pas être calculable", nom)
		}
	}
}

// --- Choix du pot ----------------------------------------------------------

func TestChoisirPot_LaDemandeLEmporte(t *testing.T) {
	a := potDeTest("a", 0.05, true)
	b := potDeTest("b", 0.06, false)
	got := choisirPot([]Pot{a, b}, b.ID.Hex())
	if got == nil || got.Name != "b" {
		t.Fatalf("le pot demandé devrait être servi, obtenu %v", got)
	}
}

func TestChoisirPot_SansDemandeLeDefaut(t *testing.T) {
	a := potDeTest("a", 0.05, false)
	b := potDeTest("b", 0.06, true)
	got := choisirPot([]Pot{a, b}, "")
	if got == nil || got.Name != "b" {
		t.Fatalf("le pot par défaut devrait être servi, obtenu %v", got)
	}
}

// Le choix de pot est persisté dans le jardin de l'utilisateur (#280). Si ce
// pot quitte la bibliothèque, le jardin doit continuer à s'afficher : on
// retombe sur le défaut plutôt que de ne rien servir.
func TestChoisirPot_PotDisparuRetombeSurLeDefaut(t *testing.T) {
	a := potDeTest("a", 0.05, false)
	b := potDeTest("b", 0.06, true)
	got := choisirPot([]Pot{a, b}, primitive.NewObjectID().Hex())
	if got == nil || got.Name != "b" {
		t.Fatalf("un pot inconnu devrait retomber sur le défaut, obtenu %v", got)
	}
}

func TestChoisirPot_AucunDefautDeclareLePremier(t *testing.T) {
	a := potDeTest("a", 0.05, false)
	b := potDeTest("b", 0.06, false)
	got := choisirPot([]Pot{a, b}, "")
	if got == nil || got.Name != "a" {
		t.Fatalf("sans défaut déclaré, le premier devrait servir, obtenu %v", got)
	}
}

func TestChoisirPot_BibliothequeVide(t *testing.T) {
	if got := choisirPot(nil, ""); got != nil {
		t.Fatalf("une bibliothèque vide ne doit servir aucun pot, obtenu %v", got)
	}
	if got := choisirPot([]Pot{}, "abc"); got != nil {
		t.Fatalf("une bibliothèque vide ne doit servir aucun pot, obtenu %v", got)
	}
}

// --- Composition -----------------------------------------------------------

func TestComposerPlante_RecoupeeRecoitUnPot(t *testing.T) {
	pot := potDeTest("cachepot_pieds", 0.058654, true)
	rep := composerPlante(planteRecoupee(socleReel()), []Pot{pot}, "")
	if rep.Pot == nil {
		t.Fatal("une plante recoupée doit être servie avec un pot")
	}
	if rep.Pot.Name != "cachepot_pieds" {
		t.Fatalf("pot servi = %q", rep.Pot.Name)
	}
}

// La régression qui compte : une plante historique ne doit rien voir changer,
// même si le client réclame un pot. Lui en ajouter un se superposerait au pot
// déjà présent dans le maillage.
func TestComposerPlante_PlanteHistoriqueInchangee(t *testing.T) {
	pot := potDeTest("cachepot_pieds", 0.058654, true)
	historique := Plant{Name: "Monstera"} // ni Potless ni PotBase
	rep := composerPlante(historique, []Pot{pot}, pot.ID.Hex())
	if rep.Pot != nil {
		t.Fatalf("une plante dont le maillage porte son pot ne doit pas en recevoir un second, obtenu %v", rep.Pot)
	}
}

func TestComposerPlante_PotlessFauxEstHistorique(t *testing.T) {
	faux := false
	pot := potDeTest("p", 0.05, true)
	rep := composerPlante(Plant{Name: "X", Potless: &faux, PotBase: socleReel()}, []Pot{pot}, "")
	if rep.Pot != nil {
		t.Fatalf("potless=false doit se comporter comme une plante historique, obtenu %v", rep.Pot)
	}
}

// Sans socle mesuré, servir un pot donnerait au client de quoi le poser au
// hasard : on préfère la plante nue, qui est visiblement incomplète.
func TestComposerPlante_SansSocleAucunPot(t *testing.T) {
	pot := potDeTest("p", 0.05, true)
	rep := composerPlante(planteRecoupee(nil), []Pot{pot}, "")
	if rep.Pot != nil {
		t.Fatalf("sans socle, aucun pot ne doit être servi, obtenu %v", rep.Pot)
	}
}

func TestComposerPlante_RebordNulAucunPot(t *testing.T) {
	plat := potDeTest("plat", 0, true)
	rep := composerPlante(planteRecoupee(socleReel()), []Pot{plat}, "")
	if rep.Pot != nil {
		t.Fatalf("un rebord nul ne doit servir aucun pot, obtenu %v", rep.Pot)
	}
}

func TestComposerPlante_BibliothequeVideNeSertAucunPot(t *testing.T) {
	rep := composerPlante(planteRecoupee(socleReel()), nil, "")
	if rep.Pot != nil {
		t.Fatalf("sans bibliothèque, aucun pot, obtenu %v", rep.Pot)
	}
	if rep.Name != "Aglaonema Mix" {
		t.Fatalf("la plante doit rester servie, obtenu %q", rep.Name)
	}
}

// --- Forme du JSON ---------------------------------------------------------

// Le JSON doit rester plat : les clients existants lisent `name`, `modelURL`…
// à la racine. Un `plant` imbriqué casserait tout le monde.
func TestPlantResponse_JSONPlatEtSansChampVide(t *testing.T) {
	pot := potDeTest("cachepot_pieds", 0.058654, true)
	brut, err := json.Marshal(composerPlante(planteRecoupee(socleReel()), []Pot{pot}, ""))
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(brut, &m); err != nil {
		t.Fatal(err)
	}
	if _, ok := m["name"]; !ok {
		t.Fatal("les champs de la plante doivent rester à la racine")
	}
	if _, ok := m["pot"]; !ok {
		t.Fatal("le pot doit être servi à la racine")
	}
	if _, ok := m["potBase"]; !ok {
		t.Fatal("potBase doit être servi : c'est lui qui permet au client de changer de pot sans réseau")
	}
	if m["potless"] != true {
		t.Fatalf("potless = %v, attendu true", m["potless"])
	}

	// Une plante historique ne doit porter aucune de ces clés.
	brut, err = json.Marshal(composerPlante(Plant{Name: "Monstera"}, []Pot{pot}, ""))
	if err != nil {
		t.Fatal(err)
	}
	m = map[string]any{}
	if err := json.Unmarshal(brut, &m); err != nil {
		t.Fatal(err)
	}
	for _, cle := range []string{"pot", "potless", "potBase"} {
		if _, present := m[cle]; present {
			t.Errorf("une plante historique ne doit pas porter %q", cle)
		}
	}
}

// Le rebord doit sortir dans le JSON du pot : sans lui, le client ne peut pas
// recalculer l'échelle quand l'utilisateur change de pot.
func TestPot_JSONPorteLeRebord(t *testing.T) {
	pot := potDeTest("cachepot_pieds", 0.058654, true)
	brut, err := json.Marshal(pot)
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(brut, &m); err != nil {
		t.Fatal(err)
	}
	for _, cle := range []string{"rimRadius", "modelURL", "id", "height"} {
		if _, ok := m[cle]; !ok {
			t.Errorf("le JSON du pot doit porter %q", cle)
		}
	}
}

// --- Hauteur réelle --------------------------------------------------------

// Aujourd'hui le client met TOUTE plante à l'échelle d'une constante — 0,5 m
// dans `GardenARPlacementView.autoScaleTargetHeightMeters` — faute de hauteur
// réelle en base. Un Yucca et une Haworthia sortent donc à la même taille.
// `heightMeters` est ce qui lève cette constante ; il est optionnel pour que
// les fiches non mesurées continuent d'y retomber plutôt que de disparaître.
func TestPlant_HeightMetersOptionnelEtOmisSiAbsent(t *testing.T) {
	brut, err := json.Marshal(Plant{Name: "Monstera"})
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(brut, &m); err != nil {
		t.Fatal(err)
	}
	if _, present := m["heightMeters"]; present {
		t.Fatal("sans mesure, le champ doit être absent, pas à zéro : un zéro ferait disparaître la plante")
	}

	h := 0.339
	brut, err = json.Marshal(Plant{Name: "Cordyline", HeightMeters: &h})
	if err != nil {
		t.Fatal(err)
	}
	m = map[string]any{}
	if err := json.Unmarshal(brut, &m); err != nil {
		t.Fatal(err)
	}
	if m["heightMeters"] != 0.339 {
		t.Fatalf("heightMeters = %v, attendu 0.339", m["heightMeters"])
	}
}

// La hauteur est celle de la plante DEPUIS LA TERRE, donc indépendante du pot :
// elle doit être servie que la plante soit recoupée ou non.
func TestComposerPlante_LaHauteurSurvitALaComposition(t *testing.T) {
	h := 0.241
	pot := potDeTest("cachepot_pieds", 0.058654, true)
	p := planteRecoupee(socleReel())
	p.HeightMeters = &h
	rep := composerPlante(p, []Pot{pot}, "")
	if rep.HeightMeters == nil || *rep.HeightMeters != h {
		t.Fatalf("hauteur perdue par la composition : %v", rep.HeightMeters)
	}
}

// --- L'invariant : une plante recoupée ne voyage jamais sans son pot --------

// La question qui a motivé ce test : « partout où les plantes sont appelées,
// si sans_pot alors on lie le pot — c'est bien respecté ? »
//
// Ça ne l'était pas. La fiche servait le pot, le catalogue non, et une plante
// recoupée arrivait donc nue dans la liste. L'invariant doit tenir à la
// SOURCE, sinon chaque nouvel appelant doit y penser — et un jour l'un d'eux
// n'y pensera pas.
func TestComposerPlante_LInvariantTientSurUneListeEntiere(t *testing.T) {
	pot := potDeTest("cachepot_pieds", 0.058654, true)
	catalogue := []Plant{
		planteRecoupee(socleReel()),
		{Name: "Monstera"}, // historique : son maillage porte déjà son pot
		planteRecoupee(socleReel()),
		planteRecoupee(nil), // recoupée mais sans socle : pose incalculable
	}

	var recoupeesAvecPot, historiquesSansPot, recoupeesSansPot int
	for _, p := range catalogue {
		rep := composerPlante(p, []Pot{pot}, "")
		switch {
		case sansPot(p) && rep.Pot != nil:
			recoupeesAvecPot++
		case sansPot(p):
			recoupeesSansPot++
		case rep.Pot == nil:
			historiquesSansPot++
		}
	}

	if recoupeesAvecPot != 2 {
		t.Errorf("les plantes recoupées posables doivent toutes recevoir un pot, obtenu %d/2", recoupeesAvecPot)
	}
	if historiquesSansPot != 1 {
		t.Errorf("une plante historique ne doit pas recevoir de pot, obtenu %d/1", historiquesSansPot)
	}
	if recoupeesSansPot != 1 {
		t.Errorf("une recoupée sans socle ne doit pas recevoir de pot qu'elle ne saurait poser, obtenu %d/1", recoupeesSansPot)
	}
}

// --- Pose servie (#695) ----------------------------------------------------
//
// Le serveur ne servait aucune pose : le client la calculait. Ça ne couvrait
// pas un moteur SANS client — le job de rendu des vignettes est headless et
// refuse délibérément d'inventer la règle. Mesuré : 51 plantes sur 123 étaient
// rendues NUES.
//
// Ces tests calquent `PlantPotCompositionTests.swift`, pour que les deux
// implémentations ne puissent pas diverger en silence.

// Les constantes DOIVENT valoir celles de `PlantPotComposer`, dans
// `ArboreUi/ArboreUi/Models/PlantPot.swift`. Ce test ne lit pas le Swift : il
// épingle les nombres pour qu'un changement d'UN seul côté fasse tomber la CI
// plutôt que de produire deux compositions différentes.
func TestConstantesDeCompositionEpinglees(t *testing.T) {
	cas := map[string]struct{ got, want float64 }{
		"partOuverture (PlantPotComposer.partOuverture)": {partOuverturePot, 0.9445},
		"retraitTerre (PlantPotComposer.retraitTerre)":   {retraitTerrePot, 0.06},
		"marge anti z-fighting":                          {margeDisquePot, 0.985},
		"épaisseur, en part de la hauteur":               {epaisseurDisque, 0.02},
	}
	for nom, c := range cas {
		if c.got != c.want {
			t.Errorf("%s = %v, attendu %v — aligner avec PlantPot.swift", nom, c.got, c.want)
		}
	}
}

func TestPoserPot_EchelleEtCentre(t *testing.T) {
	pot := potDeTest("cachepot_pieds", 0.058654, true)
	base := socleReel()

	pose, ok := poserPot(base, &pot)
	if !ok {
		t.Fatal("la pose devrait être calculable sur des valeurs relevées")
	}
	if want := base.Radius / pot.RimRadius; math.Abs(pose.Scale-want) > 1e-9 {
		t.Fatalf("échelle = %v, attendu %v", pose.Scale, want)
	}
	// Le pot est centré sur le socle, sa lèvre alignée sur `socle.y`.
	if pose.X != base.X || pose.Y != base.Y || pose.Z != base.Z {
		t.Fatalf("pose = (%v,%v,%v), attendu le centre du socle (%v,%v,%v)",
			pose.X, pose.Y, pose.Z, base.X, base.Y, base.Z)
	}
}

// LE test du disque. Son rayon ne dépend PAS du maillage : par construction,
// le rayon extérieur mis à l'échelle vaut exactement `socle.rayon`.
func TestPoserPot_RayonDuDisqueNeDependPasDuMaillage(t *testing.T) {
	base := socleReel()

	// Deux pots de rebords très différents : à socle égal, le disque doit être
	// IDENTIQUE, puisque l'échelle compense exactement le rebord.
	etroit := potDeTest("étroit", 0.03, true)
	large := potDeTest("large", 0.12, true)

	a, okA := poserPot(base, &etroit)
	b, okB := poserPot(base, &large)
	if !okA || !okB || a.Disque == nil || b.Disque == nil {
		t.Fatal("deux disques attendus")
	}
	if math.Abs(a.Disque.Rayon-b.Disque.Rayon) > 1e-12 {
		t.Fatalf("rayons différents (%v vs %v) : le disque ne devrait dépendre que du socle",
			a.Disque.Rayon, b.Disque.Rayon)
	}
	if want := base.Radius * partOuverturePot * margeDisquePot; math.Abs(a.Disque.Rayon-want) > 1e-12 {
		t.Fatalf("rayon = %v, attendu %v", a.Disque.Rayon, want)
	}
}

func TestPoserPot_DisqueTientDansLOuverture(t *testing.T) {
	pot := potDeTest("cachepot_pieds", 0.058654, true)
	base := socleReel()

	pose, _ := poserPot(base, &pot)
	if pose.Disque == nil {
		t.Fatal("disque attendu")
	}
	// Mêmes bornes que `testDisqueTientDansLOuvertureDuPot` côté iOS.
	ouverture := base.Radius * partOuverturePot
	if pose.Disque.Rayon >= ouverture {
		t.Errorf("rayon %v >= ouverture %v : le disque traverserait la paroi",
			pose.Disque.Rayon, ouverture)
	}
	if pose.Disque.Rayon <= ouverture*0.95 {
		t.Errorf("rayon %v trop étroit : l'anneau nu resterait visible", pose.Disque.Rayon)
	}
}

func TestPoserPot_DisqueEnRetraitSousLaLevreEtCentre(t *testing.T) {
	pot := potDeTest("cachepot_pieds", 0.058654, true)
	base := socleReel()

	pose, _ := poserPot(base, &pot)
	if pose.Disque == nil {
		t.Fatal("disque attendu")
	}
	if pose.Disque.Y >= pose.Y {
		t.Errorf("au ras du rebord (%v >= %v), le disque a l'air de flotter",
			pose.Disque.Y, pose.Y)
	}
	hauteur := pot.Height * pose.Scale
	if pose.Disque.Y <= pose.Y-hauteur*0.25 {
		t.Errorf("trop bas (%v), il décolle de la terre de la plante", pose.Disque.Y)
	}
	if pose.Disque.X != pose.X || pose.Disque.Z != pose.Z {
		t.Errorf("le disque doit suivre le centre du socle")
	}
}

// Une hauteur inutilisable ne doit pas empêcher de servir la POSE : un pot bien
// posé sans disque reste très au-dessus d'une plante nue.
func TestPoserPot_SansHauteurLaPoseEstServieSansDisque(t *testing.T) {
	base := socleReel()
	for nom, h := range map[string]float64{
		"hauteur nulle":    0,
		"hauteur négative": -1,
		"hauteur NaN":      math.NaN(),
		"hauteur infinie":  math.Inf(1),
	} {
		pot := potDeTest("bancal", 0.058654, true)
		pot.Height = h

		pose, ok := poserPot(base, &pot)
		if !ok {
			t.Errorf("%s : la pose devrait rester servie", nom)
			continue
		}
		if pose.Disque != nil {
			t.Errorf("%s : disque servi à tort (%+v)", nom, pose.Disque)
		}
	}
}

// NaN et Inf : toute comparaison avec NaN étant fausse, `NaN <= 0` ne rejetait
// rien. Sans conséquence tant que l'échelle n'était qu'un garde-fou local ;
// elle part maintenant sur le réseau.
func TestEchellePot_RefuseNaNEtInfini(t *testing.T) {
	cas := map[string]struct {
		rayon  float64
		rebord float64
	}{
		"socle NaN":    {math.NaN(), 0.05},
		"rebord NaN":   {0.16, math.NaN()},
		"socle +Inf":   {math.Inf(1), 0.05},
		"rebord +Inf":  {0.16, math.Inf(1)},
		"les deux NaN": {math.NaN(), math.NaN()},
	}
	for nom, c := range cas {
		pot := potDeTest("x", c.rebord, true)
		base := &PotBase{Radius: c.rayon}
		if e, ok := echellePot(base, &pot); ok {
			t.Errorf("%s : accepté à tort, échelle = %v", nom, e)
		}
		if _, ok := poserPot(base, &pot); ok {
			t.Errorf("%s : pose servie à tort", nom)
		}
	}
}

// La plante historique, dont le maillage porte déjà son pot, ne doit rien voir
// changer — pas même une pose.
func TestComposerPlante_PlanteAvecSonPotNeRecoitAucunePose(t *testing.T) {
	pot := potDeTest("cachepot_pieds", 0.058654, true)
	historique := Plant{Name: "Ficus historique", PotBase: socleReel()}

	rep := composerPlante(historique, []Pot{pot}, "")

	if rep.Pot != nil {
		t.Fatalf("aucun pot ne doit être servi, obtenu %+v", rep.Pot)
	}
}

// La pose doit atteindre le JSON, sous `pot.pose` : c'est précisément là que
// `vignettes/publier.py` la lit (`pot.get("pose")`).
func TestComposerPlante_LaPoseEstDansLeJSONSousPot(t *testing.T) {
	pot := potDeTest("cachepot_pieds", 0.058654, true)
	rep := composerPlante(planteRecoupee(socleReel()), []Pot{pot}, "")

	brut, err := json.Marshal(rep)
	if err != nil {
		t.Fatalf("sérialisation : %v", err)
	}
	var lu struct {
		Pot *struct {
			RimRadius float64 `json:"rimRadius"`
			Pose      *struct {
				Scale  float64 `json:"scale"`
				X      float64 `json:"x"`
				Y      float64 `json:"y"`
				Z      float64 `json:"z"`
				Disque *struct {
					Rayon     float64 `json:"rayon"`
					Epaisseur float64 `json:"epaisseur"`
				} `json:"disque"`
			} `json:"pose"`
		} `json:"pot"`
	}
	if err := json.Unmarshal(brut, &lu); err != nil {
		t.Fatalf("relecture : %v", err)
	}
	if lu.Pot == nil || lu.Pot.Pose == nil {
		t.Fatalf("`pot.pose` absent du JSON : le job rendrait la plante nue\n%s", brut)
	}
	if lu.Pot.Pose.Disque == nil {
		t.Fatalf("`pot.pose.disque` absent du JSON\n%s", brut)
	}
	// Le pot reste servi en entier : le client qui recalcule en a besoin.
	if lu.Pot.RimRadius != 0.058654 {
		t.Errorf("rimRadius = %v, le pot doit rester servi entier", lu.Pot.RimRadius)
	}
}
