package main

import (
	"bytes"
	"testing"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// thumbnailversion_test — issues #294, #524, #686.
//
// Ce que ces cas protègent : remplacer une vignette doit changer son empreinte,
// sinon l'image reste invisible sur tous les appareils qui l'ont déjà en cache.
// L'upload écrivait le PNG et renvoyait 200 sans toucher `versions.thumbnail` —
// un succès apparent, sans aucun effet visible.

func TestEmpreinteVignetteChangeAvecLeContenu(t *testing.T) {
	a, err := EmpreinteContenu(bytes.NewReader([]byte("vignette A")))
	if err != nil {
		t.Fatalf("empreinte A : %v", err)
	}
	b, err := EmpreinteContenu(bytes.NewReader([]byte("vignette B")))
	if err != nil {
		t.Fatalf("empreinte B : %v", err)
	}
	if a == b {
		t.Fatalf("deux contenus distincts partagent l'empreinte %q : le cache ne se renouvellerait jamais", a)
	}
	if len(a) != longueurEmpreinte {
		t.Fatalf("empreinte de %d caractères, attendu %d", len(a), longueurEmpreinte)
	}
}

func TestEmpreinteVignetteStableAContenuEgal(t *testing.T) {
	// Le pendant du cas précédent : réécrire le MÊME fichier ne doit pas faire
	// retélécharger le catalogue entier à tout le parc.
	octets := []byte("vignette identique")
	a, err := EmpreinteContenu(bytes.NewReader(octets))
	if err != nil {
		t.Fatalf("première empreinte : %v", err)
	}
	b, err := EmpreinteContenu(bytes.NewReader(octets))
	if err != nil {
		t.Fatalf("seconde empreinte : %v", err)
	}
	if a != b {
		t.Fatalf("même contenu, empreintes %q et %q", a, b)
	}
}

// vignettesAuCatalogue : taille du catalogue servi au 2026-10-23.
//
// Codée en dur à dessein. Le plafond d'envoi doit laisser passer une passe
// complète, et c'est la seule façon de faire échouer le test le jour où
// quelqu'un le rabaisse sans mesurer ce qu'il coupe.
const vignettesAuCatalogue = 123

func TestPlafondVignettesLaissePasserUnePasseComplete(t *testing.T) {
	if vignettesParMinute < vignettesAuCatalogue {
		t.Fatalf("plafond de %d par minute pour %d vignettes : une republication "+
			"s'arreterait en route, comme avec le limiteur partage a 10/min",
			vignettesParMinute, vignettesAuCatalogue)
	}
}

func TestPlafondVignettesGardeUneMarge(t *testing.T) {
	// Pile la taille du catalogue ne suffit pas : un essai repris apres un
	// echec reseau consomme un jeton de plus, et le catalogue grandit.
	if minimum := vignettesAuCatalogue + vignettesAuCatalogue/4; vignettesParMinute < minimum {
		t.Fatalf("plafond de %d, attendu au moins %d pour tenir les reprises "+
			"et la croissance du catalogue", vignettesParMinute, minimum)
	}
}

func TestPlafondVignettesResteBorne(t *testing.T) {
	// L'autre erreur : un plafond si haut qu'il ne borne plus rien. La route
	// est derriere RequireAdmin(), mais chaque envoi accepte jusqu'a 8 Mo.
	if vignettesParMinute > 1000 {
		t.Fatalf("plafond de %d par minute : jusqu'a %d Mo la minute, ce n'est "+
			"plus une limite", vignettesParMinute,
			int64(vignettesParMinute)*maxThumbnailBytes/(1<<20))
	}
}

// identifiantFiche : le resserrement qui a suivi l'alerte CodeQL « Database
// query built from user-controlled sources ». Accepter tout alphanumerique
// faisait entrer une chaine venue de l'URL dans un filtre Mongo, pour couvrir
// un cas qui n'existe pas : les 123 vignettes servies portent toutes un
// ObjectID.

func TestIdentifiantFicheAccepteUnObjectID(t *testing.T) {
	attendu := primitive.NewObjectID()
	oid, ok := identifiantFiche(attendu.Hex())
	if !ok {
		t.Fatal("un ObjectID valide doit etre accepte")
	}
	if oid != attendu {
		t.Fatalf("oid = %v, attendu %v", oid, attendu)
	}
}

func TestIdentifiantFicheToleredesEspaces(t *testing.T) {
	attendu := primitive.NewObjectID()
	if oid, ok := identifiantFiche("  " + attendu.Hex() + "\t"); !ok || oid != attendu {
		t.Fatalf("espaces autour de l'identifiant : ok=%v oid=%v", ok, oid)
	}
}

func TestIdentifiantFicheRefuseCeQuiNEstPasUnObjectID(t *testing.T) {
	// Chaque cas refuse pour une raison differente, et les trois derniers sont
	// ceux qui atteignaient le filtre Mongo et les traces avant ce changement.
	for _, brut := range []string{
		"",                          // vide
		"monstera-maison",           // alphanumerique mais pas hexadecimal
		"69e020341fe524cab5a67f4",   // 23 caracteres
		"69e020341fe524cab5a67f4dd", // 25 caracteres
		"69e020341fe524cab5a67f4z",  // caractere non hexadecimal
		"../../etc/passwd",          // traversee de chemin
		"a\nFAUSSE LIGNE DE LOG",    // forgerie de trace
		`{"$ne": null}`,             // operateur Mongo
	} {
		if oid, ok := identifiantFiche(brut); ok {
			t.Errorf("%q accepte a tort (oid=%v)", brut, oid)
		}
	}
}
