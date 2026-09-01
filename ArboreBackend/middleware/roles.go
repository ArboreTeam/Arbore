package middleware

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// roles.go — modèle d'autorisation (issue #377).
//
// Deux axes volontairement séparés, jamais fusionnés en un enum unique :
//
//   - `role` répond à « qu'as-tu le droit de faire ? »   → guest | member | admin
//   - `tier` répond à « qu'as-tu payé ? »                → free  | premium
//
// Les fusionner produirait un produit cartésien dès qu'un administrateur est
// aussi abonné, ou qu'un invité paie. `banned` reste un troisième axe, déjà
// présent avant cette issue : c'est un état de modération, pas un rôle.

// Rôles reconnus. `RoleOwner` et `RoleSupport` sont RÉSERVÉS : ils sont
// acceptés par la validation mais aucune route ne les distingue encore.
// Réserver un nom ne coûte rien ; l'ajouter après coup imposerait une migration
// des documents déjà écrits.
const (
	RoleGuest   = "guest"   // session anonyme, pas de compte, pas de sync
	RoleMember  = "member"  // compte authentifié ordinaire — le défaut
	RoleAdmin   = "admin"   // écriture catalogue, génération IA
	RoleOwner   = "owner"   // réservé : promotion d'administrateurs
	RoleSupport = "support" // réservé : lecture seule d'assistance
)

// Niveaux d'abonnement.
const (
	TierFree    = "free"
	TierPremium = "premium"
)

// Provenance du tier, conservée pour l'audit : un `premium` doit toujours être
// explicable (achat validé côté serveur, ou octroi manuel tracé).
const (
	TierSourceNone     = "none"
	TierSourceAppStore = "appstore"
	TierSourceGrant    = "grant"
)

// accessProfileKey est la clé de contexte sous laquelle FirebaseAuthMiddleware
// dépose le profil d'autorisation de la requête courante.
const accessProfileKey = "arboreAccessProfile"

// AccessProfile est l'instantané d'autorisation d'une requête. Il est construit
// une seule fois par requête, dans le middleware d'authentification.
type AccessProfile struct {
	Role   string
	Tier   string
	Banned bool
}

// LoadAccessProfileFunc lit le profil d'autorisation d'un utilisateur depuis la
// base. Reçoit le *gin.Context pour router vers la bonne base (prod ou test)
// selon le sélecteur posé par APIKeyMiddleware.
//
// Remplace l'ancien `CheckUserBannedFunc` : le middleware effectuait déjà un
// FindOne par requête pour le seul contrôle de bannissement, donc lire `role` et
// `tier` dans ce même document ne coûte aucune requête supplémentaire — et évite
// le délai de propagation d'une heure des custom claims Firebase.
//
// Contrat : un utilisateur absent de la base n'est pas une erreur. Il doit
// retourner le profil par défaut (member / free, non banni), car `POST /users`
// s'exécute nécessairement avant que le document n'existe.
var LoadAccessProfileFunc func(c *gin.Context, uid string) (AccessProfile, error)

// NormalizeRole ramène une valeur brute lue en base vers un rôle connu.
//
// Le repli est `RoleMember`, JAMAIS `RoleGuest` : un champ vide (tous les
// documents antérieurs à cette issue), une valeur inconnue ou une lecture
// dégradée doivent donner un compte ordinaire. Replier vers `guest` casserait
// l'accès des comptes existants ; replier vers `admin` serait une escalade.
// Aucun backfill n'est donc nécessaire.
func NormalizeRole(raw string) string {
	switch strings.TrimSpace(strings.ToLower(raw)) {
	case RoleGuest:
		return RoleGuest
	case RoleAdmin:
		return RoleAdmin
	case RoleOwner:
		return RoleOwner
	case RoleSupport:
		return RoleSupport
	default:
		return RoleMember
	}
}

// NormalizeTier ramène une valeur brute vers un niveau connu et applique
// l'expiration.
//
// L'expiration est vérifiée ICI, à la lecture, et non par un webhook : sans
// cela un abonnement échu resterait premium jusqu'au passage d'un job externe.
// Un `expiresAt` nil signifie « pas de date de fin connue » et laisse le tier
// inchangé (cas d'un octroi manuel permanent).
func NormalizeTier(raw string, expiresAt *time.Time, now time.Time) string {
	tier := TierFree
	if strings.TrimSpace(strings.ToLower(raw)) == TierPremium {
		tier = TierPremium
	}
	if tier == TierPremium && expiresAt != nil && now.After(*expiresAt) {
		return TierFree
	}
	return tier
}

// IsPrivilegedRole indique si le rôle donne accès aux routes d'administration.
func IsPrivilegedRole(role string) bool {
	return role == RoleAdmin || role == RoleOwner
}

// setAccessProfile dépose le profil dans le contexte de la requête.
func setAccessProfile(c *gin.Context, profile AccessProfile) {
	c.Set(accessProfileKey, profile)
}

// AccessProfileFromContext retourne le profil de la requête courante. Le second
// retour est faux si le middleware d'authentification n'a pas tourné.
func AccessProfileFromContext(c *gin.Context) (AccessProfile, bool) {
	value, exists := c.Get(accessProfileKey)
	if !exists {
		return AccessProfile{}, false
	}
	profile, ok := value.(AccessProfile)
	return profile, ok
}

// RoleFromContext retourne le rôle de la requête, ou `RoleMember` par défaut.
func RoleFromContext(c *gin.Context) string {
	if profile, ok := AccessProfileFromContext(c); ok {
		return profile.Role
	}
	return RoleMember
}

// TierFromContext retourne le niveau d'abonnement de la requête, ou `TierFree`.
func TierFromContext(c *gin.Context) string {
	if profile, ok := AccessProfileFromContext(c); ok {
		return profile.Tier
	}
	return TierFree
}

// RequireAccount ferme la route aux invités.
//
// Formulé en « tout sauf guest » plutôt qu'en liste blanche de rôles : ajouter
// un rôle à l'avenir (owner, support) ne doit pas le priver silencieusement des
// routes de compte ordinaires. Le seul rôle qui doit être exclu ici est celui
// qui, par définition, n'a pas de compte.
//
// Couvre tout ce qui suppose un compte durable : jardins, profil,
// consentements, export RGPD. Un invité est par construction lié à un seul
// appareil, ces routes n'auraient pas de sens pour lui.
func RequireAccount() gin.HandlerFunc {
	return func(c *gin.Context) {
		if RoleFromContext(c) == RoleGuest {
			c.JSON(http.StatusForbidden, gin.H{
				"error": "This action requires a registered account",
				"code":  "ACCOUNT_REQUIRED",
			})
			c.Abort()
			return
		}
		c.Next()
	}
}

// RequireRole n'autorise que les rôles explicitement listés. Réservé aux cas où
// l'énumération est le sens voulu ; préférer RequireAccount pour « pas un
// invité ».
func RequireRole(allowed ...string) gin.HandlerFunc {
	permitted := make(map[string]struct{}, len(allowed))
	for _, role := range allowed {
		permitted[role] = struct{}{}
	}

	return func(c *gin.Context) {
		role := RoleFromContext(c)
		if _, ok := permitted[role]; !ok {
			c.JSON(http.StatusForbidden, gin.H{
				"error": "This action requires a registered account",
				"code":  "ACCOUNT_REQUIRED",
			})
			c.Abort()
			return
		}
		c.Next()
	}
}
