package main

import "strings"

// Le prédicat de sûreté du foyer, répliqué depuis iOS (#792).
//
// POURQUOI UNE RÉPLIQUE PLUTÔT QU'UN SERVICE
//
// La décision vit côté client : le catalogue et le moteur de suggestions
// doivent fonctionner hors ligne, donc la logique ne peut pas être un appel
// réseau. Elle existe en Swift et doit exister ici aussi, parce que le backend
// filtre lui aussi — le contexte de catalogue qu'il bâtit pour le chat ne doit
// pas proposer ce que l'app masquerait.
//
// La duplication est assumée, et elle est tenable pour une raison précise :
// depuis #778 il n'y a plus RIEN à dériver. Ces fonctions ne lisent que des
// valeurs closes et ne font que les comparer. Vingt lignes sans interprétation
// se répliquent sans dériver — ce qui n'était pas vrai de l'analyse de prose
// qu'elles remplacent, et c'est exactement pourquoi on l'a retirée.
//
// Ce qui empêche les deux côtés de s'écarter n'est pas la discipline mais
// `fixtures/plant-traits.json` : un fichier, deux lecteurs, les mêmes verdicts
// affirmés des deux côtés.

// VerdictToxicite est le verdict rendu au lecteur, et non la valeur stockée.
//
// `irritant` et `toxic` se confondent ici : les sources les distinguent, le
// foyer non. Une plante irritante avertit comme une plante toxique.
type VerdictToxicite int

const (
	// ToxiciteNonEtablie : on a cherché sans trouver, ou on n'a pas cherché.
	// JAMAIS synonyme de « sans danger ».
	ToxiciteNonEtablie VerdictToxicite = iota
	ToxiciteSure
	ToxiciteAvertit
)

// VerdictDepuisFait lit un fait stocké. Un fait absent, vide ou hors
// vocabulaire rend NON ÉTABLI — jamais `ToxiciteSure`.
//
// Le sens de la chute compte : une valeur qu'on ne comprend pas doit coûter
// une suggestion perdue, pas une plante toxique recommandée à un foyer avec un
// chat.
func VerdictDepuisFait(f *PlantToxicityFact) VerdictToxicite {
	if f == nil {
		return ToxiciteNonEtablie
	}
	switch strings.ToLower(strings.TrimSpace(f.Value)) {
	case "safe":
		return ToxiciteSure
	case "toxic", "irritant":
		return ToxiciteAvertit
	default:
		return ToxiciteNonEtablie
	}
}

// VerdictAvecRepli ajoute le repli par drapeau, pour les fiches antérieures au
// contrat `botanicalProfile`.
//
// Seul le `true` du drapeau porte une information. Son `false` a longtemps
// voulu dire à la fois « prouvé sûr » et « pas recherché » — 65 fiches du
// catalogue étaient dans ce cas — donc il ne vaut PAS une innocuité démontrée.
func VerdictAvecRepli(f *PlantToxicityFact, drapeau *bool) VerdictToxicite {
	// Un fait PRÉSENT fait autorité, y compris quand il dit `unknown` : il
	// signifie « on a cherché sans trouver », ce qu'aucun drapeau ne sait
	// dire. Consulter le drapeau par-dessus transformerait cette absence
	// mesurée en conflit, et la plante disparaîtrait du catalogue au lieu d'y
	// figurer marquée — ce que la politique `Parcourable` cherche justement à
	// éviter.
	if f != nil && strings.TrimSpace(f.Value) != "" {
		return VerdictDepuisFait(f)
	}
	// Sans fait, le drapeau est tout ce qu'on a. Et seul son `true` porte une
	// information : son `false` a longtemps voulu dire à la fois « prouvé
	// sûr » et « pas recherché », sur 65 fiches du catalogue. Il ne vaut donc
	// PAS une innocuité démontrée.
	if drapeau != nil && *drapeau {
		return ToxiciteAvertit
	}
	return ToxiciteNonEtablie
}

// ExigenceFoyer est ce que l'utilisateur a déclaré au questionnaire.
type ExigenceFoyer struct {
	Animaux bool
	Enfants bool
}

func (e ExigenceFoyer) EstVide() bool { return !e.Animaux && !e.Enfants }

// IssueSurete : trois branches, et pas un booléen.
//
// Un booléen force à ranger l'inconnu avec l'un des deux, et c'est le piège qui
// traverse ces données depuis le début.
type IssueSurete int

const (
	SureteSatisfaite IssueSurete = iota
	SureteEnConflit
	SureteNonEtablie
)

// IssueDeSurete : LE prédicat. Un fait, sans politique d'affichage.
//
// Le pire l'emporte : un conflit sur un seul axe exigé suffit, et une
// indétermination ne se compense pas par une certitude sur l'autre axe.
func IssueDeSurete(animaux, enfants VerdictToxicite, e ExigenceFoyer) IssueSurete {
	if e.EstVide() {
		return SureteSatisfaite
	}
	var retenus []VerdictToxicite
	if e.Animaux {
		retenus = append(retenus, animaux)
	}
	if e.Enfants {
		retenus = append(retenus, enfants)
	}
	for _, v := range retenus {
		if v == ToxiciteAvertit {
			return SureteEnConflit
		}
	}
	for _, v := range retenus {
		if v == ToxiciteNonEtablie {
			return SureteNonEtablie
		}
	}
	return SureteSatisfaite
}

// PolitiqueFoyer : ce qu'on FAIT de l'issue, et ça dépend de la surface.
type PolitiqueFoyer int

const (
	// Parcourable : ce que l'utilisateur PARCOURT. Masque le conflit, laisse
	// voir l'indéterminé — l'incertitude est la nôtre, pas celle de la plante.
	Parcourable PolitiqueFoyer = iota
	// Proposable : ce que l'app PROPOSE. Masque les deux. Quand on recommande,
	// on engage sa parole ; parcourir n'engage que le regard.
	Proposable
)

// Admet dit si cette politique accepte cette issue.
func (p PolitiqueFoyer) Admet(i IssueSurete) bool {
	switch i {
	case SureteSatisfaite:
		return true
	case SureteEnConflit:
		return false
	default:
		return p == Parcourable
	}
}
