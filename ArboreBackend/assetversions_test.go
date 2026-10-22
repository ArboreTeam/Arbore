package main

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"strings"
	"testing"
)

// assetversions_test — issues #294, #295, #524.
//
// Ce que ces empreintes doivent garantir tient en deux phrases, et les deux
// erreurs opposées coûtent cher.
//
// Ne PAS changer quand le fichier change laisse un appareil sur un modèle
// périmé indéfiniment, puisque `Documents/Models/` survit aux mises à jour :
// c'est le défaut qu'on répare, celui de #292 où les testeurs gardaient du
// gris jusqu'à réinstallation.
//
// Changer quand le fichier n'a PAS changé fait retélécharger pour rien — 440 Mo
// pour les 123 light, plusieurs gigaoctets en heavy. C'est le défaut du
// compteur global de #524, celui qu'on refuse de reproduire.
//
// D'où l'insistance sur le déterminisme et sur l'indépendance des champs.

func empreinteDe(t *testing.T, s string) string {
	t.Helper()
	v, err := EmpreinteContenu(strings.NewReader(s))
	if err != nil {
		t.Fatal(err)
	}
	return v
}

func TestEmpreinteContenu_MemeContenuMemeEmpreinte(t *testing.T) {
	a := empreinteDe(t, "des octets de modele")
	b := empreinteDe(t, "des octets de modele")
	if a != b {
		t.Fatalf("empreinte non déterministe : %q puis %q — un retéléchargement de tout le catalogue à chaque passe", a, b)
	}
}

func TestEmpreinteContenu_UnSeulOctetSuffitALaChanger(t *testing.T) {
	a := empreinteDe(t, "modele version 1")
	b := empreinteDe(t, "modele version 2")
	if a == b {
		t.Fatal("un contenu différent doit donner une empreinte différente, sinon l'appareil garde le fichier périmé")
	}
}

func TestEmpreinteContenu_Longueur(t *testing.T) {
	v := empreinteDe(t, "x")
	if len(v) != longueurEmpreinte {
		t.Fatalf("longueur = %d, attendu %d", len(v), longueurEmpreinte)
	}
	for _, c := range v {
		if !strings.ContainsRune("0123456789abcdef", c) {
			t.Fatalf("caractère non hexadécimal %q dans %q — la valeur finit dans un nom de fichier et dans une URL", c, v)
		}
	}
}

func TestEmpreinteContenu_ContenuVide(t *testing.T) {
	v, err := EmpreinteContenu(strings.NewReader(""))
	if err != nil {
		t.Fatal(err)
	}
	if len(v) != longueurEmpreinte {
		t.Fatalf("un fichier vide doit tout de même rendre une empreinte, obtenu %q", v)
	}
}

// Le heavy pèse jusqu'à 80 Mo : l'empreinte se calcule en flux, pas en
// chargeant le fichier en mémoire. Ce test passe un volume que personne ne
// voudrait voir tenir dans un []byte recopié.
func TestEmpreinteContenu_GrosFichier(t *testing.T) {
	gros := make([]byte, 4<<20)
	if _, err := rand.Read(gros); err != nil {
		t.Fatal(err)
	}
	a, err := EmpreinteContenu(bytes.NewReader(gros))
	if err != nil {
		t.Fatal(err)
	}
	b, err := EmpreinteContenu(bytes.NewReader(gros))
	if err != nil {
		t.Fatal(err)
	}
	if a != b {
		t.Fatalf("empreinte instable sur un gros fichier : %q puis %q", a, b)
	}
}

type lecteurFautif struct{}

func (lecteurFautif) Read([]byte) (int, error) { return 0, errLecture }

var errLecture = errReader("lecture impossible")

type errReader string

func (e errReader) Error() string { return string(e) }

func TestEmpreinteContenu_LectureImpossible(t *testing.T) {
	if _, err := EmpreinteContenu(lecteurFautif{}); err == nil {
		t.Fatal("une lecture fautive doit remonter : une empreinte vide poserait silencieusement « fichier inchangé »")
	}
}

// --- Forme du JSON ---------------------------------------------------------

// Les trois fichiers sont distincts : remplacer le light ne doit pas faire
// retélécharger le heavy, qui pèse dix fois plus.
func TestAssetVersions_LesChampsSontIndependants(t *testing.T) {
	brut, err := json.Marshal(Plant{
		Name:     "Monstera",
		Versions: &AssetVersions{Model: "aaaaaaaa"},
	})
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(brut, &m); err != nil {
		t.Fatal(err)
	}
	v, ok := m["versions"].(map[string]any)
	if !ok {
		t.Fatalf("versions absent du JSON : %s", brut)
	}
	if v["model"] != "aaaaaaaa" {
		t.Fatalf("model = %v", v["model"])
	}
	for _, cle := range []string{"modelHeavy", "thumbnail"} {
		if _, present := v[cle]; present {
			t.Errorf("%q non calculé doit être absent, pas vide : un client ne doit pas le lire comme une version", cle)
		}
	}
}

// Une fiche sans empreinte doit ressortir exactement comme avant : le client
// retombe sur son comportement actuel plutôt que de perdre son cache.
func TestAssetVersions_AbsentesSurUneFicheNonCalculee(t *testing.T) {
	brut, err := json.Marshal(Plant{Name: "Monstera"})
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(brut, &m); err != nil {
		t.Fatal(err)
	}
	if _, present := m["versions"]; present {
		t.Fatal("sans empreinte, le champ doit être absent du JSON")
	}
}

func TestPot_VersionOmiseSiAbsente(t *testing.T) {
	brut, err := json.Marshal(Pot{Name: "cachepot", RimRadius: 0.05})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(brut), "version") {
		t.Fatalf("version vide ne doit pas sortir : %s", brut)
	}
}
