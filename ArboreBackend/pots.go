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
	"math"
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

// PotPose : où poser le pot sous cette plante.
//
// Mis à l'échelle `socle.rayon / rebord.rayon`, centré sur le socle, sa lèvre
// alignée sur `socle.y`. Référence : `PlantPotComposer.placement`, dans
// `ArboreUi/ArboreUi/Models/PlantPot.swift`.
type PotPose struct {
	Scale  float64        `json:"scale"`
	X      float64        `json:"x"`
	Y      float64        `json:"y"`
	Z      float64        `json:"z"`
	Disque *DisqueDeTerre `json:"disque,omitempty"`
}

// DisqueDeTerre : le disque à poser au fond du pot.
//
// Pourquoi il en faut un : l'atelier ne conserve la terre de la plante qu'à
// 75 % du rayon, alors que le pot est posé à 100 % de `socle.rayon`. Un anneau
// de paroi nue reste donc visible tout autour sans lui.
type DisqueDeTerre struct {
	Rayon     float64 `json:"rayon"`
	X         float64 `json:"x"`
	Y         float64 `json:"y"`
	Z         float64 `json:"z"`
	Epaisseur float64 `json:"epaisseur"`
}

// Constantes de composition. Elles décrivent CE pot, pas une règle générale :
// le jour où la bibliothèque en compte un second, ce sont des mesures à porter
// sur sa fiche.
//
// Elles doublent celles de `PlantPotComposer` côté iOS, et c'est assumé — voir
// `poserPot` pour pourquoi. Un test les épingle nommément : les changer d'un
// seul côté doit faire tomber la CI, pas diverger en silence.
const (
	partOuverturePot = 0.9445 // part du rebord occupée par l'OUVERTURE
	retraitTerrePot  = 0.06   // retrait de la face de terre sous la lèvre
	margeDisquePot   = 0.985  // marge contre le z-fighting avec la paroi
	epaisseurDisque  = 0.02   // épaisseur du disque, en part de la hauteur
)

// potServi : un pot de la bibliothèque, augmenté de sa pose sous CETTE plante.
//
// Type distinct de `Pot` à dessein : la pose dépend de la plante, et n'a donc
// aucun sens sur `GET /pots`, qui sert la bibliothèque seule. L'embarquement
// garde le JSON plat.
type potServi struct {
	Pot
	Pose *PotPose `json:"pose,omitempty"`
}

// plantResponse : la plante, augmentée du pot par défaut quand elle en a
// besoin. Le champ `Plant` est embarqué, donc le JSON reste plat et les clients
// existants ne voient aucun changement.
type plantResponse struct {
	Plant
	Pot *potServi `json:"pot,omitempty"`
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
	// Finitude, comme le fait `PlantPotComposer.placement` côté iOS. Ce n'est
	// pas redondant avec les comparaisons ci-dessus : en Go comme en Swift,
	// TOUTE comparaison avec NaN est fausse, donc `NaN <= 0` ne rejette rien.
	// Un rayon NaN en base produisait une échelle NaN.
	//
	// Longtemps sans conséquence, cette valeur ne servant que de garde-fou
	// local. Elle part maintenant sur le réseau : un NaN poserait le pot nulle
	// part, chez tous les clients à la fois.
	if !math.IsInf(base.Radius, 0) && !math.IsInf(pot.RimRadius, 0) &&
		!math.IsNaN(base.Radius) && !math.IsNaN(pot.RimRadius) {
		return base.Radius / pot.RimRadius, true
	}
	return 0, false
}

// poserPot rend la pose du pot sous cette plante, disque de terre compris.
//
// ## Pourquoi le serveur la sert, alors qu'il ne la servait pas
//
// Le choix d'origine (#623) était que le CLIENT calcule : la bibliothèque se
// charge une fois, changer de pot ne repasse pas par le serveur, et l'aperçu du
// sélecteur reste instantané. Ce choix tient toujours, et l'app continue de
// recalculer pour un pot choisi en local.
//
// Ce qu'il ne couvrait pas : un moteur SANS client. Le job de rendu des
// vignettes (#694, #695) est headless, et il refuse délibérément d'inventer la
// règle — « sinon on ne compose pas de pot plutôt que d'en inventer la règle ».
// Résultat mesuré : 51 plantes sur 123 étaient rendues NUES.
//
// Servir la pose ne retire rien au client ; elle s'ajoute pour qui ne peut pas
// la calculer.
//
// ## Le rayon du disque ne dépend pas du maillage
//
// Par construction : le rayon extérieur mis à l'échelle vaut
// `rimRadius × (socle.rayon / rimRadius)`, soit **exactement `socle.rayon`**.
// Le serveur n'a donc aucune mesure de maillage à deviner — ce qui lève
// l'objection de `PlantPotComposer.disque`, qui préfère mesurer parce que l'AR
// ne dispose pas de `rimRadius`. Ici, si.
//
// Seule la hauteur passe par la fiche (`height × échelle`).
func poserPot(base *PotBase, pot *Pot) (*PotPose, bool) {
	e, ok := echellePot(base, pot)
	if !ok {
		return nil, false
	}
	pose := &PotPose{Scale: e, X: base.X, Y: base.Y, Z: base.Z}

	// Le disque est FACULTATIF : sans hauteur de pot utilisable, on sert la
	// pose sans lui. Mieux vaut un anneau nu qu'un disque au hasard, qui
	// passerait pour un défaut d'affichage — et un pot bien posé sans disque
	// reste très au-dessus d'une plante nue.
	hauteur := pot.Height * e
	rayon := base.Radius * partOuverturePot * margeDisquePot
	if hauteur > 0 && !math.IsInf(hauteur, 0) && !math.IsNaN(hauteur) && rayon > 0 {
		pose.Disque = &DisqueDeTerre{
			Rayon:     rayon,
			X:         base.X,
			Y:         base.Y - hauteur*retraitTerrePot,
			Z:         base.Z,
			Epaisseur: hauteur * epaisseurDisque,
		}
	}
	return pose, true
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
	pose, ok := poserPot(p.PotBase, pot)
	if !ok {
		// Inchangé : sans socle exploitable, mieux vaut ne servir AUCUN pot
		// que d'en donner un que le client poserait au hasard.
		return rep
	}
	rep.Pot = &potServi{Pot: *pot, Pose: pose}
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
