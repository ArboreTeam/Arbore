package main

import (
	"bytes"
	"testing"

	"go.mongodb.org/mongo-driver/bson"
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

func TestFiltrePlanteParIDAccepteUnObjectID(t *testing.T) {
	oid := primitive.NewObjectID()
	filtre, ok := filtrePlanteParID(oid.Hex())
	if !ok {
		t.Fatal("un ObjectID valide doit être exploitable")
	}
	if got := filtre["_id"]; got != oid {
		t.Fatalf("_id = %v (%T), attendu l'ObjectID %v", got, got, oid)
	}
}

func TestFiltrePlanteParIDRetombeSurLaChaine(t *testing.T) {
	// `thumbnailPlantIDRegex` accepte tout alphanumérique : un `_id` posé à la
	// main est un identifiant valide, et le refuser perdrait l'empreinte d'une
	// fiche parfaitement servie.
	filtre, ok := filtrePlanteParID("monstera-maison")
	if !ok {
		t.Fatal("un identifiant non-ObjectID doit rester exploitable")
	}
	if got := filtre["_id"]; got != "monstera-maison" {
		t.Fatalf("_id = %v, attendu la chaîne brute", got)
	}
}

func TestFiltrePlanteParIDRefuseLeVide(t *testing.T) {
	if filtre, ok := filtrePlanteParID(""); ok {
		t.Fatalf("un identifiant vide ne doit pas produire de filtre, obtenu %v", filtre)
	}
}

func TestFiltrePlanteParIDNeViseQuUneFiche(t *testing.T) {
	// Un filtre qui ne porterait pas sur `_id` pourrait toucher plusieurs
	// fiches : l'empreinte d'une vignette n'appartient qu'à la sienne.
	filtre, ok := filtrePlanteParID(primitive.NewObjectID().Hex())
	if !ok {
		t.Fatal("filtre attendu")
	}
	if len(filtre) != 1 {
		t.Fatalf("filtre à %d clés, attendu la seule clé _id : %v", len(filtre), bson.M(filtre))
	}
	if _, présent := filtre["_id"]; !présent {
		t.Fatalf("filtre sans _id : %v", bson.M(filtre))
	}
}
