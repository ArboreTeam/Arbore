package main

// assetversions — invalider le cache d'un appareil quand un fichier servi
// change, sans réinstallation et sans nouveau build. (#294, #295, #524)
//
// Le cache iOS des modèles est indexé par **nom de fichier**, dans
// `Documents/Models/`, un dossier qu'une mise à jour d'app ne vide pas. Un
// fichier réécrit sous le même nom n'atteint donc aucun appareil l'ayant déjà
// téléchargé : c'est ce qui s'est passé avec #292, où les testeurs ont gardé
// des modèles gris jusqu'à une réinstallation.
//
// # Pourquoi une empreinte par fichier, et non un compteur global
//
// La solution apparente — une constante de version dans le binaire — est déjà
// en place pour les vignettes, et #524 a mesuré ce qu'elle coûte :
//
//   - **globale** : la changer invalide les 123 vignettes sur tous les
//     appareils pour corriger une seule image. Sur des modèles 3D ce serait
//     440 Mo en light, et plusieurs gigaoctets en heavy ;
//   - **compilée** : la changer n'atteint personne sans une nouvelle livraison
//     TestFlight, donc corriger un fichier côté serveur reste invisible.
//
// L'empreinte du contenu n'a aucun de ces deux défauts. Elle change quand les
// octets changent, jamais autrement, personne n'a à penser à l'incrémenter, et
// elle voyage avec la fiche — que le client lit déjà. Remplacer un fichier
// devient une écriture d'un champ en base.
//
// # Pourquoi pas le GET conditionnel
//
// `serveStorageObject` finit par `http.ServeContent`, qui émet déjà
// `Last-Modified` et honore `If-Modified-Since`. Un client pourrait donc
// revalider sans rien ajouter côté serveur. Mais cela coûte **une requête par
// fichier et par contrôle** — au lancement, 123 allers-retours pour apprendre
// le plus souvent que rien n'a bougé. L'empreinte arrive avec le catalogue,
// que l'app demande de toute façon : elle ne coûte pas un octet de plus.

import (
	"crypto/sha256"
	"encoding/hex"
	"io"
)

// longueurEmpreinte : nombre de caractères hexadécimaux retenus du SHA-256.
//
// Huit suffisent. Ce n'est pas une signature : la valeur ne protège de rien,
// elle sert à décider « est-ce le même fichier qu'avant ». Une collision sur
// 32 bits exigerait de remplacer un modèle par un autre dont l'empreinte
// commence par les mêmes huit caractères, ce qui n'arrive pas par accident
// dans un catalogue de quelques centaines de fichiers.
const longueurEmpreinte = 8

// AssetVersions : empreinte du contenu de chaque fichier servi pour une fiche.
//
// Un champ par fichier, parce que ce sont des fichiers distincts : remplacer
// le light ne doit pas faire retélécharger le heavy, qui pèse dix fois plus.
// Un champ vide signifie « empreinte non calculée » — le client retombe alors
// sur son comportement d'avant, il ne perd rien.
type AssetVersions struct {
	Model      string `json:"model,omitempty" bson:"model,omitempty"`           // USDZ light
	ModelHeavy string `json:"modelHeavy,omitempty" bson:"modelHeavy,omitempty"` // USDZ heavy (?lod=heavy)
	Thumbnail  string `json:"thumbnail,omitempty" bson:"thumbnail,omitempty"`   // vignette PNG
}

// EmpreinteContenu rend l'empreinte courte d'un flux d'octets.
//
// Lit en flux plutôt que d'un bloc : un modèle heavy pèse jusqu'à 80 Mo, et
// rien n'oblige à les tenir en mémoire pour les résumer.
func EmpreinteContenu(r io.Reader) (string, error) {
	h := sha256.New()
	if _, err := io.Copy(h, r); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil))[:longueurEmpreinte], nil
}
