package main

import (
	"testing"
	"time"

	"golang.org/x/time/rate"
)

// La rafale (burst) est autorisée, puis les requêtes suivantes sont refusées
// tant qu'aucun token ne s'est régénéré.
func TestUserRateLimiter_BurstThenBlock(t *testing.T) {
	// 1 token/heure, burst 3 : 3 passent, la 4e est refusée.
	rl := newUserRateLimiter(rate.Every(time.Hour), 3)
	uid := "user-a"

	for i := 0; i < 3; i++ {
		if !rl.limiterFor(uid).Allow() {
			t.Fatalf("requête %d devrait passer (dans la rafale)", i+1)
		}
	}
	if rl.limiterFor(uid).Allow() {
		t.Fatal("la 4e requête devrait être refusée (rafale épuisée)")
	}
}

// Chaque uid a son propre bucket : épuiser celui d'un utilisateur n'affecte pas
// un autre.
func TestUserRateLimiter_PerUserIsolation(t *testing.T) {
	rl := newUserRateLimiter(rate.Every(time.Hour), 1)

	if !rl.limiterFor("user-a").Allow() {
		t.Fatal("1re requête de user-a devrait passer")
	}
	if rl.limiterFor("user-a").Allow() {
		t.Fatal("2e requête de user-a devrait être refusée")
	}
	// user-b n'a jamais consommé : sa 1re requête doit passer.
	if !rl.limiterFor("user-b").Allow() {
		t.Fatal("1re requête de user-b devrait passer (bucket indépendant)")
	}
}

// limiterFor renvoie le même *rate.Limiter pour un uid donné (le bucket est
// réutilisé, pas recréé à chaque appel).
func TestUserRateLimiter_ReusesBucket(t *testing.T) {
	rl := newUserRateLimiter(rate.Every(time.Hour), 5)
	a := rl.limiterFor("user-a")
	b := rl.limiterFor("user-a")
	if a != b {
		t.Fatal("limiterFor devrait réutiliser le même bucket pour un uid donné")
	}
}
