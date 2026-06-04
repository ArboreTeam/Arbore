package main

import (
	"bytes"
	"crypto/rand"
	"testing"
)

func TestEncryptDecryptRoundTrip(t *testing.T) {
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	plaintext := []byte("apple-refresh-token-rqstoken123")

	blob, err := encryptWith(key, plaintext)
	if err != nil {
		t.Fatalf("encryptWith: %v", err)
	}
	if bytes.Contains(blob, plaintext) {
		t.Fatal("le ciphertext contient le plaintext en clair")
	}

	got, err := decryptWith(key, blob)
	if err != nil {
		t.Fatalf("decryptWith: %v", err)
	}
	if !bytes.Equal(got, plaintext) {
		t.Fatalf("round-trip: got %q want %q", got, plaintext)
	}
}

func TestDecryptWrongKeyFails(t *testing.T) {
	k1 := make([]byte, 32)
	k2 := make([]byte, 32)
	_, _ = rand.Read(k1)
	_, _ = rand.Read(k2)

	blob, err := encryptWith(k1, []byte("secret"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := decryptWith(k2, blob); err == nil {
		t.Fatal("déchiffrement avec une mauvaise clé aurait dû échouer")
	}
}

func TestDecryptTamperedFails(t *testing.T) {
	key := make([]byte, 32)
	_, _ = rand.Read(key)

	blob, err := encryptWith(key, []byte("secret"))
	if err != nil {
		t.Fatal(err)
	}
	blob[len(blob)-1] ^= 0xFF // corrompt le tag GCM
	if _, err := decryptWith(key, blob); err == nil {
		t.Fatal("déchiffrement d'un ciphertext altéré aurait dû échouer")
	}
}

func TestDecryptShortBlobFails(t *testing.T) {
	key := make([]byte, 32)
	_, _ = rand.Read(key)
	if _, err := decryptWith(key, []byte("short")); err == nil {
		t.Fatal("un blob trop court aurait dû échouer")
	}
}
