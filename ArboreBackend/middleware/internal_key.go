package middleware

import (
	"crypto/subtle"
	"net/http"

	"github.com/gin-gonic/gin"
)

// internal_key.go — authentification des appelants internes. (#696)
//
// Pourquoi une clé et non un compte Firebase. Le rendu des vignettes hors
// environnement Apple a d'abord visé `POST /models/thumbnails/:plantId`, qui
// vit sous `RequireAdmin` : clé d'API PUIS session Firebase PUIS rôle admin.
// Un robot ne pouvant pas tenir une session Firebase, la seule voie était un
// compte de service administrateur — un compte humain détourné, avec son mot
// de passe à stocker, son jeton à rafraîchir, son UID dans
// `ARBORE_ADMIN_UIDS`, et le pouvoir d'écrire tout le catalogue. Un robot qui
// publie des images n'a pas besoin d'être administrateur du produit.
//
// Ce que la clé interne autorise, et rien d'autre : lire le catalogue et
// déposer une vignette. Elle ne confère aucun rôle, n'ouvre aucune route de
// compte, et ne remplace jamais la clé d'API — les routes internes exigent les
// DEUX. Le choix de la base (prod ou test) reste celui de la clé d'API : il n'y
// a pas, et il ne doit pas y avoir, de seconde façon de désigner une base.
//
// INVARIANT : clé absente ⇒ toutes les routes internes refusent. Une variable
// non renseignée doit FERMER la porte, jamais l'ouvrir. Les instances qui ne
// servent pas de robot n'ont donc rien à configurer, et la surface n'existe pas
// chez elles.
//
// Un panic à la façon d'`APIKeyMiddlewareWithKeys` serait pire ici : la clé
// d'API est indispensable au produit, cette clé-ci est facultative. Refuser de
// démarrer faute d'un secret optionnel casserait tout déploiement qui ne s'en
// sert pas.

// HeaderInternalKey porte le secret des appelants internes.
//
// Un en-tête distinct de `X-API-Key`, et non une troisième valeur acceptée par
// celui-ci : deux secrets exigés ensemble valent mieux qu'un seul dont la
// compromission suffit, et surtout `X-API-Key` choisit la base de données. Y
// glisser une clé qui ne la choisit pas inviterait la confusion.
const HeaderInternalKey = "X-Arbore-Internal-Key"

// InternalKeyMiddleware valide `X-Arbore-Internal-Key` par comparaison à temps
// constant. La clé est résolue par l'appelant, qui préfère un fichier monté à
// une variable d'environnement (audit #338 constat 4).
func InternalKeyMiddleware(internalKey string) gin.HandlerFunc {
	// Résolu UNE fois, à la construction du routeur, et non à chaque requête :
	// le refus est alors un fait établi au démarrage, pas un test qui pourrait
	// voir l'environnement changer sous lui.
	enabled := internalKey != ""

	return func(c *gin.Context) {
		if !enabled {
			// 503 et non 404 : l'existence de la route n'est pas un secret, et
			// un 404 serait indiscernable de celui qu'un hôte mal apparié
			// renvoie déjà. Un code explicite évite de rechercher deux fois la
			// même panne.
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"error": "Internal routes are not provisioned",
				"code":  "INTERNAL_ROUTES_DISABLED",
			})
			c.Abort()
			return
		}

		supplied := c.GetHeader(HeaderInternalKey)
		if supplied == "" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "Internal key required",
				"code":  "MISSING_INTERNAL_KEY",
			})
			c.Abort()
			return
		}

		if subtle.ConstantTimeCompare([]byte(supplied), []byte(internalKey)) != 1 {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "Invalid internal key",
				"code":  "INVALID_INTERNAL_KEY",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}
