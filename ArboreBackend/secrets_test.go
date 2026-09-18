package main

import (
	"os"
	"path/filepath"
	"testing"
)

// Tests de `secretFromFileOrEnv` — audit #338, constat 4.
//
// Le constat d'origine : `MASTER_ENCRYPTION_KEY` vivait dans l'environnement du
// conteneur, donc lisible par `docker inspect` et dans `/proc/<pid>/environ`.
// Quiconque peut interroger le démon Docker lit alors tous les secrets sans
// entrer dans le conteneur.
//
// La correction a d'abord porté sur cette seule clé. Ces tests couvrent son
// extension aux trois secrets restants, et surtout le comportement de repli —
// qui est la partie risquée : une résolution trop stricte transformerait une
// erreur de montage en refus de démarrer.

func ecrireSecret(t *testing.T, contenu string) string {
	t.Helper()
	chemin := filepath.Join(t.TempDir(), "secret")
	if err := os.WriteFile(chemin, []byte(contenu), 0o600); err != nil {
		t.Fatalf("écriture du fichier de test : %v", err)
	}
	return chemin
}

func TestSecretLuDepuisUnFichierMonte(t *testing.T) {
	t.Setenv("ARBORE_TEST_SECRET_PATH", ecrireSecret(t, "valeur-du-fichier"))
	t.Setenv("ARBORE_TEST_SECRET", "valeur-de-lenvironnement")

	if got := secretFromFileOrEnv("ARBORE_TEST_SECRET"); got != "valeur-du-fichier" {
		t.Fatalf("le fichier doit primer sur l'environnement, reçu %q", got)
	}
}

func TestSecretRetombeSurLEnvironnementSansChemin(t *testing.T) {
	t.Setenv("ARBORE_TEST_SECRET_PATH", "")
	t.Setenv("ARBORE_TEST_SECRET", "valeur-de-lenvironnement")

	if got := secretFromFileOrEnv("ARBORE_TEST_SECRET"); got != "valeur-de-lenvironnement" {
		t.Fatalf("sans chemin, l'environnement doit servir, reçu %q", got)
	}
}

// Le comportement qui compte le plus.
//
// Un chemin qui ne désigne rien — montage oublié, volume mal nommé — ne doit
// PAS masquer une variable correctement posée. Refuser de démarrer pour une
// erreur de montage transformerait un durcissement en panne.
func TestUnCheminIllisibleNeMasquePasLaVariable(t *testing.T) {
	t.Setenv("ARBORE_TEST_SECRET_PATH", filepath.Join(t.TempDir(), "absent"))
	t.Setenv("ARBORE_TEST_SECRET", "valeur-de-lenvironnement")

	if got := secretFromFileOrEnv("ARBORE_TEST_SECRET"); got != "valeur-de-lenvironnement" {
		t.Fatalf("un montage manquant doit retomber sur l'environnement, reçu %q", got)
	}
}

// Même raisonnement pour un fichier présent mais vide : c'est le symptôme d'un
// secret non injecté, pas d'une valeur vide voulue.
func TestUnFichierVideRetombeSurLaVariable(t *testing.T) {
	t.Setenv("ARBORE_TEST_SECRET_PATH", ecrireSecret(t, "   \n"))
	t.Setenv("ARBORE_TEST_SECRET", "valeur-de-lenvironnement")

	if got := secretFromFileOrEnv("ARBORE_TEST_SECRET"); got != "valeur-de-lenvironnement" {
		t.Fatalf("un fichier vide doit retomber sur l'environnement, reçu %q", got)
	}
}

// Les espaces et le saut de ligne final sont retirés : un fichier écrit avec
// `echo` en porte un, et une clé d'API comparée avec lui échouerait.
func TestLesEspacesDeBordSontRetires(t *testing.T) {
	t.Setenv("ARBORE_TEST_SECRET_PATH", ecrireSecret(t, "  cle-propre\n"))

	if got := secretFromFileOrEnv("ARBORE_TEST_SECRET"); got != "cle-propre" {
		t.Fatalf("les espaces de bord doivent être retirés, reçu %q", got)
	}
}

func TestSansSourceLeSecretEstVide(t *testing.T) {
	t.Setenv("ARBORE_TEST_SECRET_PATH", "")
	t.Setenv("ARBORE_TEST_SECRET", "")

	if got := secretFromFileOrEnv("ARBORE_TEST_SECRET"); got != "" {
		t.Fatalf("sans source, le secret doit être vide, reçu %q", got)
	}
}
