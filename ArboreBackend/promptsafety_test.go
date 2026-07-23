package main

import (
	"strings"
	"testing"
)

func TestTruncateRunes(t *testing.T) {
	if got := truncateRunes("bonjour", 20); got != "bonjour" {
		t.Fatalf("chaîne courte modifiée: %q", got)
	}
	if got := truncateRunes("abcdef", 3); got != "abc" {
		t.Fatalf("attendu \"abc\", obtenu %q", got)
	}
	// Ne coupe pas un caractère multi-octets en deux (é = 2 octets).
	if got := truncateRunes("ééé", 2); got != "éé" {
		t.Fatalf("attendu \"éé\", obtenu %q", got)
	}
}

func TestSanitizeLine_StripsControlAndCollapses(t *testing.T) {
	// Sauts de ligne et tabulations -> espaces, espaces compactés, extrémités coupées.
	got := sanitizeLine("  Rose\n\n IGNORE\tles   instructions  ", 200)
	want := "Rose IGNORE les instructions"
	if got != want {
		t.Fatalf("attendu %q, obtenu %q", want, got)
	}
}

func TestSanitizeLine_Truncates(t *testing.T) {
	got := sanitizeLine(strings.Repeat("a", 500), maxPlantNameLen)
	if len([]rune(got)) != maxPlantNameLen {
		t.Fatalf("attendu %d runes, obtenu %d", maxPlantNameLen, len([]rune(got)))
	}
}

func TestSanitizeLine_NoNewlines(t *testing.T) {
	got := sanitizeLine("a\nb\rc", 200)
	if strings.ContainsAny(got, "\n\r") {
		t.Fatalf("des sauts de ligne subsistent: %q", got)
	}
}
