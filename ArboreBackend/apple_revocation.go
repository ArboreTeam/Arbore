// apple_revocation.go
//
// Sign in with Apple — révocation du compte à la suppression utilisateur
// (Apple Guideline 5.1.1(v), issue #210). Si on offre "Delete account" ET
// Sign in with Apple, on DOIT révoquer le token Apple à la suppression, sinon
// le prochain login SIWA est auto-accepté sans prompt → non-conformité = reject.
//
// Flux : au premier signin SIWA, l'app iOS envoie l'`authorization_code` à
// `POST /users/me/apple-link` ; on l'échange contre un `refresh_token` Apple
// longue durée, stocké chiffré dans Mongo. Au `DELETE /users`, on déchiffre et
// on appelle l'endpoint de révocation Apple (best-effort).
package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v4"
)

const appleAudience = "https://appleid.apple.com"

// Endpoints OAuth Apple. Déclarés en var (et non const) pour être surchargés
// par les tests (httptest). En prod ils pointent sur appleid.apple.com.
var (
	//nolint:gosec // G101 faux positif : URL d'endpoint OAuth public, pas un credential.
	appleTokenURL  = "https://appleid.apple.com/auth/token"
	appleRevokeURL = "https://appleid.apple.com/auth/revoke"
)

// appleSIWAConfig regroupe la config nécessaire à la révocation Apple.
type appleSIWAConfig struct {
	teamID   string
	keyID    string
	clientID string
	privKey  *ecdsa.PrivateKey
}

// loadAppleSIWAConfig lit la config depuis l'environnement. Erreur si un élément
// manque — le caller traite ça en best-effort (pas de blocage de la suppression).
//
// APPLE_SIWA_CLIENT_ID : pour le flux **natif iOS** (ASAuthorization), c'est le
// bundle ID de l'app (com.arboreteam.arbore), PAS le Service ID web. L'auth code
// renvoyé par ASAuthorizationAppleIDCredential est émis pour le bundle ID.
func loadAppleSIWAConfig() (*appleSIWAConfig, error) {
	teamID := strings.TrimSpace(os.Getenv("APPLE_TEAM_ID"))
	keyID := strings.TrimSpace(os.Getenv("APPLE_KEY_ID"))
	clientID := strings.TrimSpace(os.Getenv("APPLE_SIWA_CLIENT_ID"))
	if teamID == "" || keyID == "" || clientID == "" {
		return nil, errors.New("APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_SIWA_CLIENT_ID requis")
	}
	key, err := loadApplePrivateKey()
	if err != nil {
		return nil, err
	}
	return &appleSIWAConfig{teamID: teamID, keyID: keyID, clientID: clientID, privKey: key}, nil
}

// loadApplePrivateKey charge la clé .p8 (PEM PKCS8 EC) depuis APPLE_SIWA_KEY_PATH
// (chemin fichier) ou APPLE_SIWA_PRIVATE_KEY (contenu PEM direct).
func loadApplePrivateKey() (*ecdsa.PrivateKey, error) {
	var pemBytes []byte
	if path := strings.TrimSpace(os.Getenv("APPLE_SIWA_KEY_PATH")); path != "" {
		//nolint:gosec // G304 : chemin .p8 fourni par l'opérateur via env de confiance, pas un input utilisateur.
		b, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("lecture APPLE_SIWA_KEY_PATH: %w", err)
		}
		pemBytes = b
	} else if raw := strings.TrimSpace(os.Getenv("APPLE_SIWA_PRIVATE_KEY")); raw != "" {
		pemBytes = []byte(raw)
	} else {
		return nil, errors.New("APPLE_SIWA_KEY_PATH ou APPLE_SIWA_PRIVATE_KEY requis")
	}
	block, _ := pem.Decode(pemBytes)
	if block == nil {
		return nil, errors.New("clé Apple : PEM invalide")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse clé Apple PKCS8: %w", err)
	}
	ecKey, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, errors.New("clé Apple : ECDSA attendu")
	}
	return ecKey, nil
}

// generateClientSecret signe le JWT ES256 utilisé comme client_secret OAuth Apple.
func (cfg *appleSIWAConfig) generateClientSecret() (string, error) {
	now := time.Now()
	token := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{
		"iss": cfg.teamID,
		"iat": now.Unix(),
		"exp": now.Add(10 * time.Minute).Unix(),
		"aud": appleAudience,
		"sub": cfg.clientID,
	})
	token.Header["kid"] = cfg.keyID
	return token.SignedString(cfg.privKey)
}

// exchangeAuthorizationCode échange l'authorization_code (fourni par l'app iOS au
// premier signin SIWA) contre un refresh_token Apple longue durée.
func (cfg *appleSIWAConfig) exchangeAuthorizationCode(ctx context.Context, code string) (string, error) {
	secret, err := cfg.generateClientSecret()
	if err != nil {
		return "", err
	}
	form := url.Values{
		"client_id":     {cfg.clientID},
		"client_secret": {secret},
		"code":          {code},
		"grant_type":    {"authorization_code"},
	}
	var resp struct {
		RefreshToken     string `json:"refresh_token"`
		Error            string `json:"error"`
		ErrorDescription string `json:"error_description"`
	}
	if err := applePostForm(ctx, appleTokenURL, form, &resp); err != nil {
		return "", err
	}
	if resp.Error != "" {
		return "", fmt.Errorf("apple token error: %s (%s)", resp.Error, resp.ErrorDescription)
	}
	if resp.RefreshToken == "" {
		return "", errors.New("apple token: refresh_token vide")
	}
	return resp.RefreshToken, nil
}

// revokeRefreshToken révoque le refresh_token côté Apple (Guideline 5.1.1(v)).
func (cfg *appleSIWAConfig) revokeRefreshToken(ctx context.Context, refreshToken string) error {
	secret, err := cfg.generateClientSecret()
	if err != nil {
		return err
	}
	form := url.Values{
		"client_id":       {cfg.clientID},
		"client_secret":   {secret},
		"token":           {refreshToken},
		"token_type_hint": {"refresh_token"},
	}
	// /auth/revoke renvoie 200 avec un corps vide en cas de succès.
	return applePostForm(ctx, appleRevokeURL, form, nil)
}

// revokeAppleBestEffort déchiffre + révoque le refresh_token Apple sans jamais
// bloquer la suppression du compte (les échecs sont seulement logués).
func revokeAppleBestEffort(ctx context.Context, uid string, encrypted []byte) {
	cfg, err := loadAppleSIWAConfig()
	if err != nil {
		log.Printf("⚠️ delete %s: révocation Apple impossible (config: %v)", uid, err)
		return
	}
	refreshToken, err := decrypt(encrypted)
	if err != nil {
		log.Printf("⚠️ delete %s: déchiffrement refresh_token Apple échoué: %v", uid, err)
		return
	}
	if err := cfg.revokeRefreshToken(ctx, string(refreshToken)); err != nil {
		log.Printf("⚠️ delete %s: révocation Apple échouée: %v", uid, err)
		return
	}
	log.Printf("✅ delete %s: compte Apple révoqué", uid)
}

func applePostForm(ctx context.Context, endpoint string, form url.Values, out interface{}) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	httpClient := &http.Client{Timeout: 10 * time.Second}
	res, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(res.Body)
		return fmt.Errorf("apple %s: status %d: %s", endpoint, res.StatusCode, strings.TrimSpace(string(body)))
	}
	if out != nil {
		return json.NewDecoder(res.Body).Decode(out)
	}
	return nil
}
