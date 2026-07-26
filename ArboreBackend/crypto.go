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
	"strings"
	"sync"
)

var (
	encKeyOnce sync.Once
	encKey     []byte
	encKeyErr  error
)

// masterEncryptionKey charge et met en cache la clé AES 32 octets.
func masterEncryptionKey() ([]byte, error) {
	encKeyOnce.Do(func() {
		encKey, encKeyErr = resolveMasterEncryptionKey()
	})
	return encKey, encKeyErr
}

// resolveMasterEncryptionKey lit la clé maître depuis deux sources, dans cet
// ordre :
//
//  1. `MASTER_ENCRYPTION_KEY_PATH` — chemin d'un fichier monté (préféré)
//  2. `MASTER_ENCRYPTION_KEY`      — variable d'environnement (repli)
//
// Le fichier est préféré parce qu'une variable d'environnement est lisible par
// `docker inspect` et dans `/proc/<pid>/environ`. C'est exactement le
// raisonnement déjà appliqué à la clé Apple `.p8` (cf. apple_revocation.go) —
// or cette clé-ci, qui déchiffre justement les refresh tokens Apple, était
// moins bien protégée que ce qu'elle protège (audit #338 constat 4).
//
// Le repli sur l'environnement est conservé pour que la bascule soit
// progressive et réversible : les deux sources donnent la même clé, donc aucun
// token existant ne devient indéchiffrable pendant la transition.
func resolveMasterEncryptionKey() ([]byte, error) {
	if path := strings.TrimSpace(os.Getenv("MASTER_ENCRYPTION_KEY_PATH")); path != "" {
		// nolint:gosec // G304 : chemin fourni par l'opérateur via une variable
		// d'environnement de confiance, jamais par un utilisateur.
		raw, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("lecture MASTER_ENCRYPTION_KEY_PATH: %w", err)
		}
		return parseMasterEncryptionKey(strings.TrimSpace(string(raw)))
	}
	return parseMasterEncryptionKey(os.Getenv("MASTER_ENCRYPTION_KEY"))
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
