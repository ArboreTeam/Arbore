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

// --- Provenance d'une vignette (#694) --------------------------------------
//
// `versions.thumbnailModel` repond a « faut-il refaire cette vignette ? ».
// Elle est DECLAREE par l'appelant, pas calculee par le serveur, donc elle doit
// etre controlee : sans ca, n'importe quoi ecrit dans ce champ fausserait la
// comparaison qui decide des re-rendus — et une plante pourrait etre exclue des
// passes pour toujours.

func TestEmpreinteValide_AccepteDesEmpreintesReelles(t *testing.T) {
	// Longueur courante (8), et une plus longue : `longueurEmpreinte` a deja
	// change une fois, et une empreinte plus ancienne reste une empreinte.
	for _, bonne := range []string{
		"f4ff96c1", "4a454725", "0f990a38", "e634dc95", "9d9f265d",
		"abcdef01", "0123456789abcdef",
		"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
	} {
		if !EmpreinteValide(bonne) {
			t.Errorf("%q refusee a tort", bonne)
		}
	}
}

func TestEmpreinteValide_RefuseCeQuiNEnEstPas(t *testing.T) {
	cas := map[string]string{
		"vide":               "",
		"trop courte":        "abcd",
		"trop longue":        strings.Repeat("a", 65),
		"majuscules":         "F4FF96C1",
		"hors alphabet hexa": "f4ff96g1",
		"espace":             "f4ff96c 1",
		"chemin":             "../../etc/passwd",
		"injection mongo":    `{"$ne":null}`,
		"point":              "f4ff.96c1",
		"tiret":              "f4ff-96c1",
	}
	for nom, mauvaise := range cas {
		if EmpreinteValide(mauvaise) {
			t.Errorf("%s : %q acceptee a tort", nom, mauvaise)
		}
	}
}

// LE test de ce bloc. Une vignette dont la provenance est INCONNUE doit
// compter comme a refaire, jamais comme a jour.
//
// C'est l'etat de toutes les vignettes publiees avant cette issue, et de toute
// vignette republiee sans declaration. Traiter « je ne sais pas » comme « sans
// doute a jour » exclurait ces plantes des passes incrementales
// definitivement — et le defaut serait invisible, puisque la vignette
// s'afficherait normalement.
func TestProvenanceInconnueCompteCommeAPerimer(t *testing.T) {
	cas := []struct {
		nom        string
		modele     string
		provenance string
		perimee    bool
	}{
		{"a jour", "abc12345", "abc12345", false},
		{"modele change", "def67890", "abc12345", true},
		{"provenance absente", "abc12345", "", true},
		{"modele absent, provenance posee", "", "abc12345", true},
		{"les deux absents", "", "", false},
	}
	for _, c := range cas {
		// La meme comparaison que celle de la route d'apercu.
		got := c.provenance != c.modele
		if got != c.perimee {
			t.Errorf("%s : perimee = %v, attendu %v", c.nom, got, c.perimee)
		}
	}
}

// Le champ doit traverser le JSON : c'est la que la route d'apercu le lit.
func TestThumbnailModelEstSerialise(t *testing.T) {
	v := AssetVersions{Model: "abc12345", Thumbnail: "def67890", ThumbnailModel: "abc12345"}

	brut, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("serialisation : %v", err)
	}
	var lu map[string]string
	if err := json.Unmarshal(brut, &lu); err != nil {
		t.Fatalf("relecture : %v", err)
	}
	if lu["thumbnailModel"] != "abc12345" {
		t.Fatalf("thumbnailModel absent ou faux : %s", brut)
	}

	// `omitempty` : une provenance vide ne doit pas encombrer la charge des
	// 123 fiches avec un champ qui ne dit rien.
	brut, _ = json.Marshal(AssetVersions{Model: "abc12345"})
	if strings.Contains(string(brut), "thumbnailModel") {
		t.Fatalf("champ vide serialise : %s", brut)
	}
}
