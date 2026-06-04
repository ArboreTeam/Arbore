package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/golang-jwt/jwt/v4"
)

// reqForm lit le corps x-www-form-urlencoded d'une requête de test sans passer
// par r.ParseForm()/r.FormValue() (que gosec G120 flagge faute de limite de
// taille — non pertinent ici, corps de test contrôlé).
func reqForm(t *testing.T, r *http.Request) url.Values {
	t.Helper()
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		t.Fatal(err)
	}
	v, err := url.ParseQuery(string(raw))
	if err != nil {
		t.Fatal(err)
	}
	return v
}

func newTestAppleConfig(t *testing.T) *appleSIWAConfig {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return &appleSIWAConfig{
		teamID:   "TEAM123456",
		keyID:    "KEY1234567",
		clientID: "com.arboreteam.arbore",
		privKey:  key,
	}
}

func TestGenerateClientSecret(t *testing.T) {
	cfg := newTestAppleConfig(t)

	secret, err := cfg.generateClientSecret()
	if err != nil {
		t.Fatalf("generateClientSecret: %v", err)
	}

	parsed, err := jwt.Parse(secret, func(tok *jwt.Token) (interface{}, error) {
		if _, ok := tok.Method.(*jwt.SigningMethodECDSA); !ok {
			t.Fatalf("méthode de signature inattendue: %v", tok.Header["alg"])
		}
		return &cfg.privKey.PublicKey, nil
	})
	if err != nil || !parsed.Valid {
		t.Fatalf("JWT client_secret invalide: %v", err)
	}

	if parsed.Header["kid"] != cfg.keyID {
		t.Errorf("kid: got %v want %v", parsed.Header["kid"], cfg.keyID)
	}
	claims := parsed.Claims.(jwt.MapClaims)
	if claims["iss"] != cfg.teamID {
		t.Errorf("iss: got %v want %v", claims["iss"], cfg.teamID)
	}
	if claims["sub"] != cfg.clientID {
		t.Errorf("sub: got %v want %v", claims["sub"], cfg.clientID)
	}
	if claims["aud"] != appleAudience {
		t.Errorf("aud: got %v want %v", claims["aud"], appleAudience)
	}
}

func TestExchangeAuthorizationCode(t *testing.T) {
	cfg := newTestAppleConfig(t)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		form := reqForm(t, r)
		if got := form.Get("grant_type"); got != "authorization_code" {
			t.Errorf("grant_type: %s", got)
		}
		if got := form.Get("code"); got != "the-auth-code" {
			t.Errorf("code: %s", got)
		}
		if got := form.Get("client_id"); got != cfg.clientID {
			t.Errorf("client_id: %s", got)
		}
		if form.Get("client_secret") == "" {
			t.Error("client_secret manquant")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"refresh_token":"rt-12345"}`))
	}))
	defer srv.Close()

	old := appleTokenURL
	appleTokenURL = srv.URL
	defer func() { appleTokenURL = old }()

	rt, err := cfg.exchangeAuthorizationCode(context.Background(), "the-auth-code")
	if err != nil {
		t.Fatalf("exchange: %v", err)
	}
	if rt != "rt-12345" {
		t.Fatalf("refresh_token: got %q want rt-12345", rt)
	}
}

func TestExchangeAuthorizationCodeAppleError(t *testing.T) {
	cfg := newTestAppleConfig(t)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"error":"invalid_grant","error_description":"bad code"}`))
	}))
	defer srv.Close()

	old := appleTokenURL
	appleTokenURL = srv.URL
	defer func() { appleTokenURL = old }()

	if _, err := cfg.exchangeAuthorizationCode(context.Background(), "x"); err == nil {
		t.Fatal("une erreur Apple aurait dû remonter")
	}
}

func TestRevokeRefreshToken(t *testing.T) {
	cfg := newTestAppleConfig(t)

	called := false
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		form := reqForm(t, r)
		if got := form.Get("token"); got != "rt-to-revoke" {
			t.Errorf("token: %s", got)
		}
		if got := form.Get("token_type_hint"); got != "refresh_token" {
			t.Errorf("token_type_hint: %s", got)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	old := appleRevokeURL
	appleRevokeURL = srv.URL
	defer func() { appleRevokeURL = old }()

	if err := cfg.revokeRefreshToken(context.Background(), "rt-to-revoke"); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	if !called {
		t.Fatal("l'endpoint de révocation Apple n'a pas été appelé")
	}
}
