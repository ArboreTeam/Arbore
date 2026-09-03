package main

import (
	"context"
	"os"
	"regexp"
	"sort"
	"strings"
	"testing"
	"time"
)

// Le job supprime des données de production sur la foi d'un système externe.
// Ces tests verrouillent les gardes qui rendent cela acceptable — pas le
// chemin nominal, qui exige une base Mongo dont l'environnement de test ne
// dispose pas.

// TestReconcileRefusesEmptyFirebaseSet est la garde la plus importante du job.
//
// Une énumération Firebase vide ferait passer TOUS les uid Mongo pour
// orphelins : le job viderait la base. Le `db` nil n'est pas un artifice de
// test, il prouve que le refus intervient AVANT toute lecture de la base.
func TestReconcileRefusesEmptyFirebaseSet(t *testing.T) {
	report, err := reconcileGuests(context.Background(), nil, map[string]struct{}{}, reconcileOptions{})
	if err == nil {
		t.Fatal("un ensemble Firebase vide doit interrompre le job, pas déclencher une purge totale")
	}
	if len(report.Orphans) != 0 {
		t.Fatalf("aucun orphelin ne doit être retenu, %d trouvé(s)", len(report.Orphans))
	}
}

// TestResolveGraceNeverDisablesItself : omettre la période de grâce doit
// retomber sur 7 jours, jamais sur zéro.
func TestResolveGraceNeverDisablesItself(t *testing.T) {
	for _, requested := range []time.Duration{0, -time.Hour, -defaultReconcileGrace} {
		if got := resolveGrace(requested); got != defaultReconcileGrace {
			t.Errorf("resolveGrace(%v) = %v, attendu %v", requested, got, defaultReconcileGrace)
		}
	}
	if got := resolveGrace(48 * time.Hour); got != 48*time.Hour {
		t.Errorf("une durée explicite doit être respectée, obtenu %v", got)
	}
}

func TestDefaultGraceIsSevenDays(t *testing.T) {
	if defaultReconcileGrace != 7*24*time.Hour {
		t.Fatalf("période de grâce = %v, attendu 7 jours (#393)", defaultReconcileGrace)
	}
}

// TestReconcileCollectionsMatchPurge verrouille l'accord entre les deux moitiés
// du job : `uidBearingCollections` décide QUI est orphelin, `purgeUserData`
// décide CE QU'ON EFFACE.
//
// Si elles divergent, le job supprime un compte en laissant derrière lui
// exactement les données personnelles orphelines qu'il est censé éliminer — ou
// bien il ignore un uid qui n'existe que dans la collection oubliée. Aucune des
// deux listes n'étant introspectable à l'exécution, le test lit la source.
func TestReconcileCollectionsMatchPurge(t *testing.T) {
	source, err := os.ReadFile("account_cleanup.go")
	if err != nil {
		t.Fatalf("lecture de account_cleanup.go: %v", err)
	}

	body := string(source)
	start := strings.Index(body, "func purgeUserData(")
	if start < 0 {
		t.Fatal("purgeUserData introuvable : le test doit être mis à jour avec le code")
	}

	purged := map[string]bool{}
	for _, match := range regexp.MustCompile(`db\.Collection\("([^"]+)"\)`).FindAllStringSubmatch(body[start:], -1) {
		purged[match[1]] = true
	}
	// deleteLegacyCommunityData est appelée par purgeUserData et porte sa propre
	// collection ; elle compte dans le périmètre effacé.
	if strings.Contains(body[start:], "deleteLegacyCommunityData(") {
		purged["community_posts"] = true
	}

	if !equalKeySets(purged, uidBearingCollections) {
		t.Fatalf("désaccord entre les collections purgées %v et celles qui déterminent l'orphelinat %v\n"+
			"Toute collection ajoutée à l'une doit l'être à l'autre.",
			sortedKeys(purged), sortedKeys(uidBearingCollections))
	}
}

func equalKeySets[A any, B any](left map[string]A, right map[string]B) bool {
	if len(left) != len(right) {
		return false
	}
	for key := range left {
		if _, ok := right[key]; !ok {
			return false
		}
	}
	return true
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

// TestCommunityPostsUsesUserIdField : la collection héritée n'indexe pas `uid`
// mais `userId`. Une uniformisation hâtive du champ ferait silencieusement
// passer tous ses documents pour non-orphelins.
func TestCommunityPostsUsesUserIdField(t *testing.T) {
	if field := uidBearingCollections["community_posts"]; field != "userId" {
		t.Fatalf("community_posts doit être filtrée sur userId, obtenu %q", field)
	}
}
