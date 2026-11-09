package main

import "strings"

// Les traits de plante en VALEURS CLOSES (#792).
//
// POURQUOI CE FICHIER EXISTE
//
// Jusqu'ici, sept traits — taille, nature, couleurs, buts d'aménagement,
// floraison, facilité, capacité de pose — se dérivaient de la PROSE des fiches,
// côté iOS, par listes de mots-clés sur le texte TRADUIT. Trois défauts en
// découlaient :
//
//  1. un booléen ne sait dire qu'une moitié de la vérité : `flowering: false`
//     ne voulait pas dire « ne fleurit pas », il faisait retomber sur la prose,
//     et une description mentionnant « fleur » suffisait à déclarer la plante
//     fleurie — la forme exacte du `toxicToPets: false` corrigé par #778 ;
//  2. un trait dépendait de la langue du lecteur : la même plante sortait
//     `large` en français et `unknown` en allemand selon la formulation du
//     traducteur ;
//  3. un mot-clé appariait sans frontière de mot.
//
// Le correctif n'est pas un meilleur analyseur, c'est l'absence d'analyseur :
// les traits sont des faits stockés, au même titre que `petToxicity`, avec leur
// provenance et un `unknown` possible et explicite.
//
// LES DEUX RÈGLES QUI GOUVERNENT TOUT CE FICHIER
//
// « Une valeur absente se dit `unknown` et ne se devine pas. » C'est la règle
// de `PlantToxicityFact`, et elle a déjà évité un accident.
//
// « Un décodage indulgent tombe vers le PLANCHER. » Une valeur hors
// vocabulaire devient `unknown` — jamais une valeur affirmative. Le sens de la
// chute compte : ne pas comprendre une valeur doit coûter une suggestion
// perdue, pas un geste impossible proposé à l'utilisateur.
//
// LECTURE ET ÉCRITURE NE SE RESSEMBLENT PAS
//
// À la LECTURE, on est indulgent : `ListeFermeeDepuisFait` écarte ce qu'elle ne
// comprend pas plutôt que de faire échouer la fiche entière.
//
// À l'ÉCRITURE, on refuse : `ValiderTraitsDuProfil` rejette la requête au lieu
// de corriger en silence. Corriger à l'écriture perdrait la trace de ce que
// l'écrivain croyait écrire, et c'est exactement ainsi que la base s'était
// remplie de `authoritative`, `authoritative-genus` et `derived` là où le
// lecteur attendait `high` (#780).

// VersionSchemaBotanique est la version courante de `PlantBotanicalProfile`.
//
// Passée de 1 à 2 par #792 : le profil gagne les champs de traits. Aucun
// lecteur ne compare cette valeur aujourd'hui (iOS la décode sans l'exploiter,
// le web la déclare optionnelle), donc l'incrément est déclaratif : il permet à
// un lecteur de SAVOIR qu'il lit la forme ancienne, il ne lui impose rien.
const VersionSchemaBotanique = 2

// indexVocabulaire associe la forme minuscule de chaque valeur à sa forme
// CANONIQUE. Le vocabulaire est en camelCase (`greenPlant`) : comparer en
// minuscules sans réécrire derrière rendrait `greenplant`, qui n'appartient à
// aucun des deux côtés du contrat.
func indexVocabulaire(valeurs []string) map[string]string {
	index := make(map[string]string, len(valeurs))
	for _, v := range valeurs {
		index[strings.ToLower(v)] = v
	}
	return index
}

// valeurCanonique normalise casse et espaces, et rend la forme canonique.
func valeurCanonique(vocabulaire map[string]string, v string) (string, bool) {
	canonique, ok := vocabulaire[strings.ToLower(strings.TrimSpace(v))]
	return canonique, ok
}

// TailleInconnue et TraitInconnu sont le PLANCHER de leurs vocabulaires :
// la valeur vers laquelle tombe tout ce qui n'est pas compris.
const (
	TailleInconnue = "unknown"
	TraitInconnu   = "unknown"
)

// taillesValides est le vocabulaire fermé de `PlantBotanicalProfile.Size`.
//
// Il porte `unknown` comme valeur de PLEIN DROIT, et non comme l'absence du
// champ : `unknown` dit « on a regardé sans conclure », ce qu'une clé absente
// ne distingue pas de « on n'a pas regardé ». C'est le modèle qu'on tenait déjà
// côté iOS (`PlantCatalogSize` porte `unknown` depuis toujours) et celui de la
// toxicité.
var taillesValides = indexVocabulaire([]string{"small", "medium", "large", "unknown"})

// traitsTriEtatValides est le vocabulaire fermé des sept traits qui étaient des
// booléens : `flowering`, `easyCare`, `compact`, `climbing`, `trailing`,
// `humidityLoving`, `airPurifying`.
//
// Trois états, pas deux, et c'est tout l'objet du changement : un `no` est une
// AFFIRMATION (« la source dit explicitement que non » — la valeur
// « Feuillage décoratif » du champ « Période de floraison » en est une), un
// champ vide est un SILENCE. Les confondre dans un booléen est le défaut que le
// correctif de la toxicité vient de payer deux fois.
var traitsTriEtatValides = indexVocabulaire([]string{"yes", "no", "unknown"})

// naturesValides est le vocabulaire fermé de `Kinds`, relevé de
// `PlantCatalogKind` côté iOS — rien d'inventé, sauf `conifer`.
//
// `conifer` est AJOUTÉ : la typologie de #777 porte `conifere` sur 39 fiches et
// ce port n'avait aucune cible. Le rabattre sur `tree` ou `shrub` perdrait une
// distinction que l'utilisateur voit.
//
// `retombante` (46 fiches) n'entre volontairement PAS ici : ce n'est pas une
// nature mais un port, et il appartient à `goals.createCascade` et au trait
// `trailing`. Le `port` alimente donc DEUX champs selon la valeur, et
// `groundcover` vient des `usages` et non du port : `kinds` se compose de deux
// sources, ce qui est écrit ici pour ne pas être redécouvert.
var naturesValides = indexVocabulaire([]string{
	"greenPlant",
	"floweringPlant",
	"cactusSucculent",
	"palm",
	"fern",
	"orchid",
	"tree",
	"shrub",
	"perennial",
	"annual",
	"grass",
	"groundcover",
	"climbing",
	"aromaticEdible",
	"conifer",
})

// butsValides est le vocabulaire fermé de `Goals`, relevé de `PlantCatalogGoal`.
var butsValides = indexVocabulaire([]string{
	"addColor",
	"createPrivacy",
	"addVolume",
	"coverWall",
	"createCascade",
	"coverGround",
	"attractPollinators",
	"edibleAromatic",
	"focalPoint",
})

// couleursValides est le vocabulaire fermé de `Colors`, relevé de
// `PlantCatalogColor`. `variegated` et `flowering` n'y sont pas : ils relèvent
// de l'apparence et du trait `flowering`, pas d'une couleur.
//
// `silver` et `brown` ont été ajoutés après le premier lot de remplissage, qui
// a mesuré ce que leur absence coûtait : les bases horticoles traitent
// `Gray/Silver` et `Brown/Copper` comme des couleurs de feuille de plein
// droit, et **78 fiches** du corpus étaient mal décrites sans elles.
//
// Deux cas ont tranché la question. `Olea europaea` (14 fiches) est donnée
// `Gray/Silver; Green` : la ramener à `green` perd exactement ce qui fait
// qu'un olivier ressemble à un olivier. Et `Salvia yangii` porte
// `Gray/Silver` comme SEULE couleur de feuille — sans `silver`, aucune valeur
// n'était disponible pour son feuillage.
//
// Les laîches de couleur (`Carex`, `Brown/Copper; Green; Red/Burgundy`)
// n'avaient elles non plus aucune valeur juste ; le lot les a laissées vides
// plutôt que d'écrire `orange`, qui aurait été une approximation et non une
// couleur dominante.
var couleursValides = indexVocabulaire([]string{
	"white",
	"yellow",
	"orange",
	"red",
	"pink",
	"purple",
	"blue",
	"green",
	"silver",
	"brown",
	"dark",
})

// posesValides est le vocabulaire fermé de `Placement`, relevé de
// `ARPlacementMode`.
//
// C'est le champ le plus grave des cinq : il décide d'une CAPACITÉ PHYSIQUE de
// pose. Il remplace deux listes de mots-clés qui embarquaient des noms de
// genres botaniques en dur (`pothos`, `hoya`, `rhipsalis`, `senecio`…) dans du
// code d'interface, appariaient sans frontière de mot — `contains("hoya")`
// apparie n'importe quelle chaîne contenant ces quatre lettres — et exigeaient
// une modification du binaire à chaque plante grimpante ajoutée. La conséquence
// d'une erreur n'y est pas un badge inexact mais un geste impossible : une
// plante déclarée posable au mur alors qu'elle ne l'est pas.
var posesValides = indexVocabulaire([]string{"floor", "wall", "ceiling"})

// TailleValide dit si une valeur appartient au vocabulaire fermé de `Size`.
// Une valeur inconnue doit être traitée comme `unknown`, jamais comme `large`.
func TailleValide(v string) bool {
	_, ok := valeurCanonique(taillesValides, v)
	return ok
}

// TraitTriEtatValide dit si une valeur appartient au vocabulaire fermé des
// traits tri-état. Une valeur inconnue doit être traitée comme `unknown`,
// jamais comme `yes` ni comme `no` : `no` est une affirmation.
func TraitTriEtatValide(v string) bool {
	_, ok := valeurCanonique(traitsTriEtatValides, v)
	return ok
}

// NaturePlanteValide dit si une valeur appartient au vocabulaire fermé de `Kinds`.
func NaturePlanteValide(v string) bool {
	_, ok := valeurCanonique(naturesValides, v)
	return ok
}

// ButAmenagementValide dit si une valeur appartient au vocabulaire fermé de `Goals`.
func ButAmenagementValide(v string) bool {
	_, ok := valeurCanonique(butsValides, v)
	return ok
}

// CouleurPlanteValide dit si une valeur appartient au vocabulaire fermé de `Colors`.
func CouleurPlanteValide(v string) bool {
	_, ok := valeurCanonique(couleursValides, v)
	return ok
}

// PoseValide dit si une valeur appartient au vocabulaire fermé de `Placement`.
func PoseValide(v string) bool {
	_, ok := valeurCanonique(posesValides, v)
	return ok
}

// TailleDepuisFait lit la taille stockée. Un fait absent, vide ou hors
// vocabulaire rend `unknown` — jamais une taille affirmée.
//
// Il n'y a volontairement AUCUN repli par drapeau ici, contrairement aux traits
// tri-état : `flags.compact` ne dit pas une taille, et l'ancien `size()` le
// consultait comme un indice avant de retomber sur 20 mots-clés. Déduire
// `small` d'un « compacte » serait exactement le raisonnement qu'on retire.
func TailleDepuisFait(f *PlantTraitFact) string {
	if f == nil {
		return TailleInconnue
	}
	if canonique, ok := valeurCanonique(taillesValides, f.Value); ok {
		return canonique
	}
	return TailleInconnue
}

// TraitDepuisFait lit un trait tri-état. Un fait absent, vide ou hors
// vocabulaire rend `unknown`.
//
// Le plancher est `unknown` et non `no` : rendre `no` transformerait notre
// silence en une affirmation sur la plante, ce qui est précisément le défaut
// que les booléens portaient.
func TraitDepuisFait(f *PlantTraitFact) string {
	if f == nil {
		return TraitInconnu
	}
	if canonique, ok := valeurCanonique(traitsTriEtatValides, f.Value); ok {
		return canonique
	}
	return TraitInconnu
}

// TraitAvecRepli ajoute le repli par drapeau, pour les fiches antérieures au
// contrat `botanicalProfile`.
//
// C'est la transposition EXACTE de `VerdictAvecRepli`, et pour les mêmes
// raisons :
//
//  1. un fait PRÉSENT fait autorité, y compris quand il dit `unknown` — il
//     signifie « on a regardé sans conclure », ce qu'aucun drapeau ne sait
//     dire. Consulter le drapeau par-dessus transformerait une absence MESURÉE
//     en affirmation : c'est le défaut que le correctif de la toxicité vient de
//     payer (199 axes concernés, 108 plantes masquées à tort) ;
//  2. sans fait, le drapeau est tout ce qu'on a, et seul son `true` informe ;
//  3. son `false` ne vaut PAS une négation démontrée. Il a voulu dire à la fois
//     « la source dit non » et « personne n'a regardé », donc il rend
//     `unknown` et jamais `no`.
//
// Le repli existe parce que la migration des données n'est pas instantanée,
// pas parce qu'on tient à lire les drapeaux : une fois les faits remplis, il ne
// s'exécute plus. Il reste nommé et isolé pour qu'on puisse le retirer d'un
// seul endroit.
func TraitAvecRepli(f *PlantTraitFact, drapeau *bool) string {
	if f != nil && strings.TrimSpace(f.Value) != "" {
		return TraitDepuisFait(f)
	}
	if drapeau != nil && *drapeau {
		return "yes"
	}
	return TraitInconnu
}

// ListeFermee est le résultat de la lecture d'une liste en vocabulaire fermé.
//
// `Renseignee` existe parce qu'une liste VIDE et une liste ABSENTE ne disent
// pas la même chose, et qu'aucune liste Go ne les distingue :
//
//   - fait absent        → `Renseignee: false` : on ne sait pas. C'est l'`unknown`
//     des champs scalaires, que les listes ne peuvent pas porter comme valeur.
//   - fait présent, vide → `Renseignee: true`, aucune valeur : on a cherché, et
//     aucune valeur du vocabulaire ne s'applique. C'est une affirmation.
//
// `Rejetees` conserve ce qui a été écarté, en clair. Sans lui, une liste dont
// toutes les valeurs sont hors vocabulaire se lirait exactement comme une liste
// vide affirmée — et une liste affirmée vide est une affirmation, pas une perte
// de données silencieuse.
type ListeFermee struct {
	Valeurs    []string
	Renseignee bool
	Rejetees   []string
}

// EstVideAffirmee dit si la source a conclu qu'aucune valeur ne s'applique,
// par opposition à une liste qu'on n'a pas su lire ou qu'on n'a pas remplie.
func (l ListeFermee) EstVideAffirmee() bool {
	return l.Renseignee && len(l.Valeurs) == 0 && len(l.Rejetees) == 0
}

// ListeFermeeDepuisFait lit une liste en vocabulaire fermé, avec indulgence.
//
// Elle écarte les valeurs hors vocabulaire au lieu de faire échouer la fiche
// entière : le profil est optionnel de bout en bout pour se migrer par
// morceaux, et une clé que nous ne comprenons pas encore ne doit pas emporter
// le soleil, la température et les dimensions avec elle.
//
// L'ordre d'origine est conservé et les doublons sont retirés : la liste sert à
// afficher et à filtrer, pas à compter.
func ListeFermeeDepuisFait(f *PlantStringListFact, vocabulaire map[string]string) ListeFermee {
	if f == nil {
		return ListeFermee{}
	}
	liste := ListeFermee{Renseignee: true}
	vus := make(map[string]struct{}, len(f.Value))
	for _, brute := range f.Value {
		canonique, ok := valeurCanonique(vocabulaire, brute)
		if !ok {
			liste.Rejetees = append(liste.Rejetees, brute)
			continue
		}
		if _, dejaVu := vus[canonique]; dejaVu {
			continue
		}
		vus[canonique] = struct{}{}
		liste.Valeurs = append(liste.Valeurs, canonique)
	}
	return liste
}

// NaturesDepuisFait lit `Kinds`.
func NaturesDepuisFait(f *PlantStringListFact) ListeFermee {
	return ListeFermeeDepuisFait(f, naturesValides)
}

// ButsDepuisFait lit `Goals`.
func ButsDepuisFait(f *PlantStringListFact) ListeFermee {
	return ListeFermeeDepuisFait(f, butsValides)
}

// CouleursDepuisFait lit `Colors`.
func CouleursDepuisFait(f *PlantStringListFact) ListeFermee {
	return ListeFermeeDepuisFait(f, couleursValides)
}

// PosesDepuisFait lit `Placement`.
//
// Une pose non renseignée ne vaut PAS « posable au sol » : c'est au lecteur de
// décider ce qu'il fait d'une capacité inconnue, et il doit pouvoir voir
// qu'elle est inconnue.
func PosesDepuisFait(f *PlantStringListFact) ListeFermee {
	return ListeFermeeDepuisFait(f, posesValides)
}

// ErreurTrait nomme le champ fautif et la valeur refusée.
//
// Elle nomme la VALEUR parce qu'un refus qui ne la dit pas oblige l'écrivain à
// deviner, et parce que c'est cette trace qui a manqué quand la base s'est
// remplie d'un vocabulaire de provenance que personne ne lisait.
type ErreurTrait struct {
	Champ  string
	Valeur string
}

func (e ErreurTrait) Error() string {
	return "valeur hors vocabulaire pour « " + e.Champ + " » : « " + e.Valeur + " »"
}

// ValiderTraitsDuProfil rend toutes les valeurs de traits hors vocabulaire du
// profil, et REFUSE plutôt que de corriger.
//
// Elle ne contrôle que les champs de traits de #792. La toxicité, la fiabilité
// et le reste du profil ne sont pas validés ici : des fiches réelles portent
// encore des valeurs de provenance héritées (`unresolved`), et refuser leur
// réécriture bloquerait la migration même qui doit les corriger. Ce périmètre
// est un choix, pas un oubli.
//
// Toutes les fautes sont rendues, et non la première : un écrivain corrigé un
// champ à la fois reposte autant de fois qu'il a de fautes.
func ValiderTraitsDuProfil(p *PlantBotanicalProfile) []ErreurTrait {
	if p == nil {
		return nil
	}
	var fautes []ErreurTrait

	scalaires := []struct {
		champ  string
		fait   *PlantTraitFact
		valide func(string) bool
	}{
		{"size", p.Size, TailleValide},
		{"flowering", p.Flowering, TraitTriEtatValide},
		{"easyCare", p.EasyCare, TraitTriEtatValide},
		{"compact", p.Compact, TraitTriEtatValide},
		{"climbing", p.Climbing, TraitTriEtatValide},
		{"trailing", p.Trailing, TraitTriEtatValide},
		{"humidityLoving", p.HumidityLoving, TraitTriEtatValide},
		{"airPurifying", p.AirPurifying, TraitTriEtatValide},
	}
	for _, s := range scalaires {
		if s.fait == nil {
			continue
		}
		// Une valeur vide n'est pas une faute : c'est l'absence, et l'absence se
		// lit `unknown`. Ne pas remplir un champ reste permis ; mal le remplir
		// ne l'est pas.
		if strings.TrimSpace(s.fait.Value) == "" {
			continue
		}
		if !s.valide(s.fait.Value) {
			fautes = append(fautes, ErreurTrait{Champ: s.champ, Valeur: s.fait.Value})
		}
	}

	listes := []struct {
		champ  string
		fait   *PlantStringListFact
		valide func(string) bool
	}{
		{"kinds", p.Kinds, NaturePlanteValide},
		{"goals", p.Goals, ButAmenagementValide},
		{"colors", p.Colors, CouleurPlanteValide},
		{"placement", p.Placement, PoseValide},
	}
	for _, l := range listes {
		if l.fait == nil {
			continue
		}
		for _, v := range l.fait.Value {
			if !l.valide(v) {
				fautes = append(fautes, ErreurTrait{Champ: l.champ, Valeur: v})
			}
		}
	}

	return fautes
}
