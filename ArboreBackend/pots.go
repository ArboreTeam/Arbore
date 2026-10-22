package main

// pots — bibliothèque de pots et composition plante + pot (#609 étape 6, #623, #280).
//
// L'atelier 3D produit désormais des plantes **recoupées**, sans leur pot, et
// mesure le socle sur lequel le pot vient se poser. Un client ne peut donc pas
// afficher une telle plante seule : il lui faut un pot, et l'échelle de ce pot
// dépend à la fois du socle de la plante et du rebord du pot.
//
// D'où le choix d'architecture : un pot **par défaut** est résolu côté serveur
// et servi dans la charge de la plante, plutôt que par un second appel. Un
// appel séparé serait toujours en série derrière celui de la plante, puisque
// le client ne sait qu'après coup si la plante a besoin d'un pot ; une plante
// sans pot s'afficherait nue le temps de l'aller-retour.
//
// En revanche, **changer** de pot ne repasse pas par le serveur. Le socle est
// une mesure de la plante, indépendante du pot ; la bibliothèque se charge une
// fois et se garde ; la pose vaut `socle.rayon / rebord.rayon`. Le client a
// donc tout pour recalculer en local, ce qui rend l'aperçu du sélecteur
// instantané et permet de rouvrir un jardin hors ligne. Resservir la fiche
// entière — traductions, profil botanique, images — pour une division serait
// du gaspillage, et dupliquer la règle des deux côtés la ferait diverger.
//
// Les plantes historiques, dont le maillage contient son pot, ne sont pas
// touchées : sans `potless`, la réponse est exactement celle d'avant.

import (
	"context"
	"net/http"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// PotBase : le socle mesuré par l'atelier, en unités du modèle de la plante
// (pas en centimètres — le maillage n'est pas à l'échelle réelle).
// C'est le `socle` de l'atelier, renommé en anglais comme le reste de l'API.
type PotBase struct {
	X           float64 `json:"x" bson:"x"`                     // centre du socle
	Y           float64 `json:"y" bson:"y"`                     // hauteur de la lèvre, où s'aligne le haut du pot
	Z           float64 `json:"z" bson:"z"`                     //
	Radius      float64 `json:"radius" bson:"radius"`           // rayon du socle
	GroundY     float64 `json:"groundY" bson:"groundY"`         // ligne de terre (#185)
	PlantHeight float64 `json:"plantHeight" bson:"plantHeight"` // hauteur du végétal seul
}

// Pot : une entrée de la bibliothèque. La bibliothèque est libre — un pot va
// sous n'importe quelle plante — faute d'élément qui justifie des
// compatibilités par plante (question ouverte de #623).
type Pot struct {
	ID        primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	Name      string             `json:"name" bson:"name"`
	ModelURL  string             `json:"modelURL" bson:"modelURL"`
	RimRadius float64            `json:"rimRadius" bson:"rimRadius"` // rayon du rebord, unités du modèle de pot
	Height    float64            `json:"height" bson:"height"`
	Default   bool               `json:"default" bson:"default"`                     // servi quand le client n'en demande aucun
	Version   string             `json:"version,omitempty" bson:"version,omitempty"` // empreinte du contenu du USDZ (#294)
}

// plantResponse : la plante, augmentée du pot par défaut quand elle en a
// besoin. Le champ `Plant` est embarqué, donc le JSON reste plat et les clients
// existants ne voient aucun changement.
//
// Aucune pose n'est servie : le client la calcule depuis `potBase` et
// `rimRadius`, règle de #623 — pot mis à l'échelle `socle.rayon / rebord.rayon`,
// centré sur le socle, lèvre alignée sur `socle.y`. C'est la même ligne pour le
// pot par défaut et pour un pot choisi ensuite, donc une seule implémentation.
type plantResponse struct {
	Plant
	Pot *Pot `json:"pot,omitempty"`
}

// sansPot : vrai si le maillage de la plante ne contient pas son pot.
func sansPot(p Plant) bool {
	return p.Potless != nil && *p.Potless
}

// choisirPot retient le pot demandé, et retombe sur le pot par défaut quand la
// demande ne correspond à rien.
//
// Le repli est volontaire : le choix de pot est persisté dans le jardin de
// l'utilisateur (#280). Si ce pot disparaît de la bibliothèque, le jardin doit
// continuer à s'afficher — une erreur ici viderait une scène déjà enregistrée.
// À défaut de pot par défaut, le premier de la liste ; à défaut de liste, nil.
func choisirPot(pots []Pot, demande string) *Pot {
	if len(pots) == 0 {
		return nil
	}
	if demande != "" {
		for i := range pots {
			if pots[i].ID.Hex() == demande {
				return &pots[i]
			}
		}
	}
	for i := range pots {
		if pots[i].Default {
			return &pots[i]
		}
	}
	return &pots[0]
}

// echellePot rend le facteur d'échelle du pot sous cette plante, et dit s'il a
// un sens. Le serveur ne sert pas cette valeur — le client la recalcule à
// chaque changement de pot — mais il s'en sert comme garde-fou : sans socle
// mesuré, ou avec un rebord nul, mieux vaut ne servir aucun pot que d'en donner
// un que le client poserait au hasard.
func echellePot(base *PotBase, pot *Pot) (float64, bool) {
	if base == nil || pot == nil || pot.RimRadius <= 0 || base.Radius <= 0 {
		return 0, false
	}
	return base.Radius / pot.RimRadius, true
}

// composerPlante assemble la réponse. Une plante dont le maillage porte déjà
// son pot ressort inchangée, même si le client en demande un : lui en ajouter
// un second le superposerait au maillage.
func composerPlante(p Plant, pots []Pot, demande string) plantResponse {
	rep := plantResponse{Plant: p}
	if !sansPot(p) {
		return rep
	}
	pot := choisirPot(pots, demande)
	if pot == nil {
		return rep
	}
	if _, ok := echellePot(p.PotBase, pot); !ok {
		return rep
	}
	rep.Pot = pot
	return rep
}

// ---------- HTTP ----------

func chargerPots(c *gin.Context) ([]Pot, error) {
	collection := getDatabaseForRequest(c).Collection("pots")
	cursor, err := collection.Find(context.Background(), bson.M{})
	if err != nil {
		return nil, err
	}
	defer func() { _ = cursor.Close(context.Background()) }()

	var pots []Pot
	if err := cursor.All(context.Background(), &pots); err != nil {
		return nil, err
	}
	return pots, nil
}

// getPots sert la bibliothèque, pour le sélecteur de pot de #280.
func getPots(c *gin.Context) {
	pots, err := chargerPots(c)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Erreur lors de la récupération des pots"}) // nolint:misspell
		return
	}
	if pots == nil {
		pots = []Pot{}
	}
	c.JSON(http.StatusOK, pots)
}
