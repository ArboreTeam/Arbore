// crypto.go
//
// Chiffrement symétrique au repos pour les secrets utilisateur sensibles
// (issue #210 : refresh_token Apple). AES-256-GCM avec une clé maître chargée
// depuis l'environnement (`MASTER_ENCRYPTION_KEY`, 32 octets encodés en hex).
package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"sync"
)

var (
	encKeyOnce sync.Once
	encKey     []byte
	encKeyErr  error
)

// masterEncryptionKey charge et met en cache la clé AES 32 octets depuis
// MASTER_ENCRYPTION_KEY (64 caractères hex). Erreur si absente ou mal formée.
func masterEncryptionKey() ([]byte, error) {
	encKeyOnce.Do(func() {
		encKey, encKeyErr = parseMasterEncryptionKey(os.Getenv("MASTER_ENCRYPTION_KEY"))
	})
	return encKey, encKeyErr
}

func parseMasterEncryptionKey(raw string) ([]byte, error) {
	if raw == "" {
		return nil, errors.New("MASTER_ENCRYPTION_KEY non défini")
	}
	key, err := hex.DecodeString(raw)
	if err != nil {
		return nil, fmt.Errorf("MASTER_ENCRYPTION_KEY invalide (hex attendu): %w", err)
	}
	if len(key) != 32 {
		return nil, fmt.Errorf("MASTER_ENCRYPTION_KEY doit faire 32 octets (64 hex), reçu %d", len(key))
	}
	return key, nil
}

// encrypt scelle `plaintext` avec AES-256-GCM sous la clé maître.
// Sortie = nonce || ciphertext.
func encrypt(plaintext []byte) ([]byte, error) {
	key, err := masterEncryptionKey()
	if err != nil {
		return nil, err
	}
	return encryptWith(key, plaintext)
}

// decrypt ouvre un blob nonce||ciphertext produit par encrypt, sous la clé maître.
func decrypt(blob []byte) ([]byte, error) {
	key, err := masterEncryptionKey()
	if err != nil {
		return nil, err
	}
	return decryptWith(key, blob)
}

// encryptWith chiffre avec une clé explicite (AES-256-GCM). Testable sans env.
func encryptWith(key, plaintext []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, err
	}
	return gcm.Seal(nonce, nonce, plaintext, nil), nil
}

// decryptWith déchiffre avec une clé explicite. Testable sans env.
func decryptWith(key, blob []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if len(blob) < gcm.NonceSize() {
		return nil, errors.New("ciphertext trop court")
	}
	nonce, ct := blob[:gcm.NonceSize()], blob[gcm.NonceSize():]
	return gcm.Open(nil, nonce, ct, nil)
}
