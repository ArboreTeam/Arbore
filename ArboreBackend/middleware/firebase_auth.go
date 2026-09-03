package middleware

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"github.com/gin-gonic/gin"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
)

var firebaseAuth *auth.Client

// Taille de page de l'énumération Firebase (maximum autorisé par l'API).
const firebaseListPageSize = 1000

const adminContextKey = "arboreIsAdmin"

// signInProviderAnonymous est la valeur de `firebase.sign_in_provider` pour une
// session Firebase Anonymous Auth. C'est la seule source de vérité du rôle
// `guest` : elle est signée par Firebase dans le token, contrairement à un champ
// Mongo qui serait modifiable par le porteur du compte.
const signInProviderAnonymous = "anonymous"

// isReleaseMode reports whether the server runs in production.
// In release mode Firebase auth is REQUIRED — any missing credential must fail fast.
func isReleaseMode() bool {
	return os.Getenv("GIN_MODE") == "release"
}

// InitFirebase initializes the Firebase Admin SDK using the service account file.
// In release mode, any credential problem is fatal: the backend must refuse to
// start rather than running with authentication disabled.
func InitFirebase() error {
	serviceAccountPath := os.Getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
	if serviceAccountPath == "" {
		if isReleaseMode() {
			return fmt.Errorf("FIREBASE_SERVICE_ACCOUNT_PATH is required in release mode")
		}
		log.Println("⚠️  FIREBASE_SERVICE_ACCOUNT_PATH non défini, auth Firebase désactivée (dev only)")
		return nil
	}

	// Check that the file exists and is a regular file (not a directory).
	// nolint:gosec // serviceAccountPath comes from trusted FIREBASE_SERVICE_ACCOUNT_PATH environment variable
	info, err := os.Stat(serviceAccountPath)
	if err != nil {
		if isReleaseMode() {
			return fmt.Errorf("firebase credentials file unreadable in release mode (%s): %w", serviceAccountPath, err)
		}
		// nolint:gosec // serviceAccountPath comes from trusted environment variable
		log.Printf("⚠️  Fichier Firebase introuvable (%s): %v — auth Firebase désactivée (dev only)", serviceAccountPath, err)
		return nil
	}
	if info.IsDir() {
		if isReleaseMode() {
			return fmt.Errorf("FIREBASE_SERVICE_ACCOUNT_PATH points to a directory in release mode: %s", serviceAccountPath)
		}
		// nolint:gosec // serviceAccountPath comes from trusted environment variable
		log.Printf("⚠️  FIREBASE_SERVICE_ACCOUNT_PATH pointe vers un dossier, pas un fichier (%s) — auth Firebase désactivée (dev only)", serviceAccountPath)
		return nil
	}

	// Read service account file
	// nolint:gosec // serviceAccountPath comes from trusted FIREBASE_SERVICE_ACCOUNT_PATH environment variable
	serviceAccountJSON, err := os.ReadFile(serviceAccountPath)
	if err != nil {
		return err
	}

	// nolint:staticcheck // WithCredentialsJSON is the recommended approach for server environments with explicit credential files
	opt := option.WithCredentialsJSON(serviceAccountJSON)
	app, err := firebase.NewApp(context.Background(), nil, opt)
	if err != nil {
		return err
	}

	firebaseAuth, err = app.Auth(context.Background())
	if err != nil {
		return err
	}

	log.Println("✅ Firebase Admin SDK initialisé")
	return nil
}

// FirebaseAuthMiddleware validates Firebase ID tokens and extracts user UID
func FirebaseAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(401, gin.H{
				"error": "Authorization header required",
				"code":  "MISSING_AUTH_HEADER",
			})
			c.Abort()
			return
		}

		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(401, gin.H{
				"error": "Invalid authorization header format (expected: Bearer <token>)",
				"code":  "INVALID_AUTH_FORMAT",
			})
			c.Abort()
			return
		}

		idToken := parts[1]

		// Si Firebase n'est pas initialisé, fail-closed en prod, fail-open en dev.
		// En release mode, InitFirebase() aurait dû empêcher le lancement du backend,
		// donc atteindre ce point signifie qu'un bug ou une race a laissé firebaseAuth nil
		// — on refuse la requête au lieu de laisser passer sans authentification.
		if firebaseAuth == nil {
			if isReleaseMode() {
				log.Println("❌ Firebase non initialisé en release mode — requête refusée")
				c.JSON(503, gin.H{
					"error": "Authentication service unavailable",
					"code":  "AUTH_UNAVAILABLE",
				})
				c.Abort()
				return
			}
			log.Println("⚠️  Firebase non initialisé — token non vérifié, auth désactivée (dev only)")
			c.Set("uid", "unauthenticated")
			setAccessProfile(c, AccessProfile{Role: RoleMember, Tier: TierFree})
			c.Set(adminContextKey, isAdminUID("unauthenticated"))
			c.Next()
			return
		}

		token, err := firebaseAuth.VerifyIDToken(c.Request.Context(), idToken)
		if err != nil {
			log.Printf("❌ Token validation failed: %v", err)
			c.JSON(401, gin.H{
				"error": "Invalid or expired token",
				"code":  "INVALID_TOKEN",
			})
			c.Abort()
			return
		}

		uid := token.UID

		isGuest := token.Firebase.SignInProvider == signInProviderAnonymous

		// La lecture du profil est faite pour TOUTE identité, invités compris
		// (#381). La version initiale la sautait pour les sessions anonymes, au
		// motif qu'un invité n'a pas de document utilisateur — vrai dans le cas
		// nominal, mais cela rendait `banned` structurellement inopposable à un
		// invité : le seul levier de modération du backend devenait inapplicable
		// à toute une population, et le deviendrait aussi aux comptes anonymes
		// liés ensuite à une identité permanente, qui conservent leur uid.
		//
		// Bannir un invité consiste donc à créer un document `users` portant son
		// uid et `banned: true`, exactement comme pour un membre. Le coût est
		// d'une requête indexée sur `uid` — l'index existe (cf. indexes.go), et
		// c'est le prix d'un contrôle de modération qui s'applique à tous.
		profile := AccessProfile{Role: RoleMember, Tier: TierFree}
		if LoadAccessProfileFunc != nil {
			loaded, err := LoadAccessProfileFunc(c, uid)
			if err != nil {
				log.Printf("❌ Error loading access profile: %v", err)
				c.JSON(500, gin.H{
					"error": "Internal server error",
					"code":  "DATABASE_ERROR",
				})
				c.Abort()
				return
			}
			profile = loaded
		}

		// Le rôle `guest` est imposé APRÈS la lecture, et écrase ce que porte le
		// document. Deux raisons :
		//
		//   - `sign_in_provider` est signé par Firebase ; un document Mongo est
		//     modifiable par le porteur du compte via les autres endpoints. Le
		//     token fait donc autorité sur le rôle.
		//   - L'écrasement ne concerne que `Role` et `Tier` : `Banned`, lu juste
		//     au-dessus, survit et reste opposable.
		if isGuest {
			profile = applyGuestOverride(profile)
		}

		if profile.Banned {
			c.JSON(403, gin.H{
				"error": "Account banned",
				"code":  "ACCOUNT_BANNED",
			})
			c.Abort()
			return
		}

		// Le rôle administrateur a deux sources d'autorité : le document Mongo
		// et le custom claim Firebase. Le claim est signé par Firebase, donc il
		// survit à une compromission de la base — c'est de la défense en
		// profondeur, pas une redondance. `ARBORE_ADMIN_UIDS` reste le mécanisme
		// d'amorçage pour désigner les premiers administrateurs.
		//
		// Une session anonyme n'est jamais privilégiée, quoi que porte le token :
		// promouvoir un compte sans identité vérifiée n'aurait aucun sens.
		isAdmin := false
		if !isGuest {
			isAdmin = IsPrivilegedRole(profile.Role) ||
				tokenHasAdminRole(token.Claims) ||
				isAdminUID(uid)
			if isAdmin && !IsPrivilegedRole(profile.Role) {
				profile.Role = RoleAdmin
			}
		}

		// #110 : exiger un email vérifié, SAUF pour la création initiale du
		// compte (POST /users) — le document Mongo doit pouvoir être créé juste
		// après le signup, avant que l'utilisateur clique le lien de vérif.
		// Google / Apple renvoient email_verified=true ; seuls les comptes
		// email/mot de passe non vérifiés sont bloqués.
		//
		// Les invités sont hors de ce contrôle : un compte anonyme n'a pas
		// d'email du tout, le gate le bloquerait sur toutes les routes (#377).
		if !isGuest && requiresVerifiedEmail(c.Request.Method, c.FullPath()) {
			verified, _ := token.Claims["email_verified"].(bool)
			if !verified {
				c.JSON(403, gin.H{
					"error": "Email not verified",
					"code":  "EMAIL_NOT_VERIFIED",
				})
				c.Abort()
				return
			}
		}

		c.Set("uid", uid)
		setAccessProfile(c, profile)
		c.Set(adminContextKey, isAdmin)

		if email, ok := token.Claims["email"].(string); ok {
			c.Set("email", email)
		}

		c.Next()
	}
}

// Account creation and deletion must remain available before email
// verification: otherwise an unverified user could create server-side data but
// would be unable to exercise the right to erase it.
func requiresVerifiedEmail(method, fullPath string) bool {
	return fullPath != "/users" || (method != http.MethodPost && method != http.MethodDelete)
}

// RequireAdmin protects catalogue mutation and plant-generation endpoints.
// The preferred source is the Firebase custom claim `admin: true`. The
// ARBORE_ADMIN_UIDS allow-list is a bootstrap/recovery mechanism for assigning
// the first administrators without trusting the API key embedded in the app.
func RequireAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		isAdmin, _ := c.Get(adminContextKey)
		if allowed, ok := isAdmin.(bool); !ok || !allowed {
			c.JSON(403, gin.H{
				"error": "Administrator role required",
				"code":  "ADMIN_REQUIRED",
			})
			c.Abort()
			return
		}
		c.Next()
	}
}

func tokenHasAdminRole(claims map[string]interface{}) bool {
	if admin, ok := claims["admin"].(bool); ok && admin {
		return true
	}
	if role, ok := claims["role"].(string); ok && strings.EqualFold(strings.TrimSpace(role), "admin") {
		return true
	}
	return false
}

func isAdminUID(uid string) bool {
	uid = strings.TrimSpace(uid)
	if uid == "" {
		return false
	}
	for _, candidate := range strings.Split(os.Getenv("ARBORE_ADMIN_UIDS"), ",") {
		if strings.TrimSpace(candidate) == uid {
			return true
		}
	}
	return false
}

// DeleteFirebaseUser removes the authentication identity after the application
// data has been erased. It deliberately fails closed in release mode.
func DeleteFirebaseUser(ctx context.Context, uid string) error {
	if firebaseAuth == nil {
		if isReleaseMode() {
			return fmt.Errorf("firebase authentication service unavailable")
		}
		return nil
	}
	err := firebaseAuth.DeleteUser(ctx, uid)
	if auth.IsUserNotFound(err) {
		return nil
	}
	return err
}

// ListAllUIDs énumère tous les uid existants dans Firebase Auth.
//
// Support du job de réconciliation Firebase ↔ Mongo (#393), qui supprime les
// données Mongo dont l'uid n'existe plus côté Firebase — le nettoyage
// automatique des comptes anonymes inactifs (activé le 2026-09-02) les fait
// disparaître au bout de 30 jours.
//
// Deux propriétés sont indispensables à la sûreté de l'appelant :
//
//   - **Fail-closed.** Toute erreur — réseau, quota, credentials — renvoie une
//     erreur et AUCUN ensemble partiel. Un appelant qui recevrait une liste
//     tronquée conclurait à l'absence des uid manquants et les effacerait. La
//     seule réponse acceptable à « je ne sais pas » est de ne rien supprimer.
//   - **Énumération complète et paginée**, plutôt qu'un GetUser par uid : un
//     échec isolé ne peut pas être confondu avec une absence, et le nombre
//     d'appels API ne croît pas avec la taille de la base.
func ListAllUIDs(ctx context.Context) (map[string]struct{}, error) {
	if firebaseAuth == nil {
		return nil, fmt.Errorf("firebase auth non initialisée : impossible d'énumérer les comptes")
	}

	uids := make(map[string]struct{})
	pager := iterator.NewPager(firebaseAuth.Users(ctx, ""), firebaseListPageSize, "")
	for {
		var page []*auth.ExportedUserRecord
		nextPageToken, err := pager.NextPage(&page)
		if err != nil {
			return nil, fmt.Errorf("énumération Firebase interrompue (aucune suppression ne doit en découler): %w", err)
		}
		for _, user := range page {
			if user != nil && user.UID != "" {
				uids[user.UID] = struct{}{}
			}
		}
		if nextPageToken == "" {
			return uids, nil
		}
	}
}
