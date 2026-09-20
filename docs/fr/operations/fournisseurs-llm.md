# Fournisseurs LLM — état, quotas et bascule

Arbore appelle un modèle de langage sur deux routes : l'assistant de jardinage
(`POST /chat`) et le diagnostic de santé des plantes (`POST /diagnose`). Cette
page décrit ce qui tourne aujourd'hui, ce que coûtent les quotas gratuits, et ce
que le code devrait apprendre à faire pour basculer d'un fournisseur à l'autre.

## État mesuré au 2026-09-20

| | Valeur | Source |
|---|---|---|
| Abstraction | `LLMProvider` (Name, Generate) | [`ArboreBackend/llmprovider.go`](../../../ArboreBackend/llmprovider.go) |
| Implémentations | **une seule** — Gemini | [`gemini_provider.go`](../../../ArboreBackend/gemini_provider.go) |
| Modèle | `gemini-2.5-flash`, surchargeable par `GEMINI_MODEL` | `defaultGeminiModel` |
| Modèle Mistral | `ministral-8b-2512` — **seule la famille Ministral est accordée** | `defaultMistralModel` |
| Sélection | `AI_PROVIDER` lu **une fois au démarrage** | `initLLMProvider()` |
| Clé | **une seule, partagée par tous les utilisateurs** | `GEMINI_API_KEY` |
| Timeout | 60 s | `http.Client{Timeout: ...}` |
| Image max | 6 Mo après décodage base64 | `validateAIImage` |

L'abstraction est saine : les handlers manipulent des types neutres
(`LLMRequest`, `LLMResult`) et ignorent tout du fournisseur concret. Ajouter
Mistral ou Groq, c'est écrire une implémentation — le `case "mistral"` attend
déjà en commentaire dans `initLLMProvider()`.

Trois limites, en revanche, sont structurelles.

**Le fournisseur est figé au démarrage.** `activeLLMProvider` est une variable
globale posée une fois. Rien ne peut en changer à l'exécution, donc rien ne peut
réagir à un quota épuisé autrement qu'en redémarrant le conteneur avec une autre
variable d'environnement.

**Les deux routes partagent le même modèle.** `generateLLM` est appelé à
l'identique depuis `handleGeminiChat` et `handleGeminiDiagnose` : la requête ne
porte aucune notion de finalité. Impossible aujourd'hui d'envoyer le chat vers
un modèle léger et le diagnostic vers un modèle vision, alors que leurs coûts
n'ont rien à voir.

**Aucune des deux routes n'interroge la base.** Voir plus bas.

## Le diagnostic n'est pas augmenté par notre catalogue

Question récurrente, réponse mesurée : **non, le scan de santé ne fait pas de
RAG**. Les handlers `/chat` et `/diagnose` ne contiennent **aucun** accès Mongo.

Ce que `/diagnose` envoie au modèle :

- l'image JPEG en base64 ;
- le nom de plante saisi par l'utilisateur, assaini et présenté explicitement
  comme une donnée et non comme une instruction ;
- quatre ratios colorimétriques calculés **sur l'appareil** (vert, jaune, brun,
  taches blanches) ;
- un prompt système de phytopathologie.

Les 123 fiches du catalogue — leurs soins, leur toxicité, leur
`botanicalProfile` — ne sont jamais consultées. L'espèce que le modèle renvoie
n'est pas non plus réconciliée avec le catalogue : elle est normalisée
(`normalizeDiagnose`) puis rendue telle quelle.

C'est un choix par défaut, pas une décision documentée. Deux conséquences :
le modèle peut nommer une espèce absente du catalogue, et il ne sait rien des
conditions que l'utilisateur a déjà déclarées pour ce jardin.

## Quotas Arbore, à ne pas confondre avec ceux du fournisseur

Le backend applique ses propres limites, par utilisateur et par palier
(anonyme / connecté / premium) :

| Route | Par minute | Par 24 h (anon / connecté / premium) |
|---|---|---|
| `/chat` | 20 | 10 / 100 / 500 |
| `/diagnose` | 6 | 3 / 20 / 100 |

Ces chiffres protègent la **clé partagée** du projet ; ils ne connaissent rien
des quotas réels de Google. Rien ne relie aujourd'hui les deux : Arbore peut
très bien autoriser un appel que Gemini refusera en 429.

Le rapport 1 pour 5 entre diagnostic et chat traduit déjà l'intuition juste —
une requête qui porte une image coûte bien plus cher qu'un tour de conversation.

## Le régime des données en palier gratuit — vérifié le 2026-09-20

C'est le critère qui décide, avant le quota et avant la vitesse. Arbore transmet
des **photos prises par les gens chez eux**. Voici ce que disent les conditions,
lues à la source.

### Ce que Google dit de son palier gratuit

Les conditions de l'API Gemini séparent « Unpaid Services » et « Paid Services ».
Pour le palier gratuit :

> Google uses the content you submit to the Services and any generated responses
> to provide, improve, and develop Google products and services

> human reviewers may read, annotate, and process your API input and output

Et surtout, la phrase qui tranche :

> **Do not submit sensitive, confidential, or personal information to the Unpaid
> Services.**

Google dissocie les données du compte et de la clé avant relecture, mais la
relecture humaine des images reste prévue. Le palier payant exclut l'usage
d'amélioration : *« Google doesn't use your prompts or responses to improve our
products »*, la conservation s'y limitant à la détection d'abus.

**Arbore tourne aujourd'hui sur le palier gratuit et y envoie des photos
d'intérieurs.** C'est exactement ce que la phrase ci-dessus demande de ne pas
faire. Le constat est suivi dans une issue dédiée.

### Mistral n'est pas le refuge évident

Contre-intuitif, et c'est pourquoi il faut le lire : **le palier gratuit
« Experiment » de Mistral est opté-IN par défaut** dans le programme
d'amélioration. Les paliers payants, eux, ne sont pas utilisés pour
l'entraînement, et le plan Scale en est exclu d'office.

**Deux réglages, pas un**, sur <https://admin.mistral.ai/plateforme/privacy> :

| Réglage | État voulu | Pourquoi |
|---|---|---|
| *Data usage for improving our services* | **désactivé** | c'est l'opt-out proprement dit ; le palier gratuit est opté-IN |
| *Enable Labs models* | **désactivé** | son propre texte dit que les données servent à l'entraînement *« regardless of my subscription plan or opt-out settings »* — l'activer **annule** le premier |

Le second est le piège. Il n'annule pas l'opt-out par accident de conception :
il le dit noir sur blanc, dans la case à cocher. Activer les modèles Labs, c'est
accepter l'entraînement quoi qu'on ait réglé par ailleurs.

**Corollaire pour `MISTRAL_MODEL`** : ne jamais y poser un modèle Labs. Le nom
du modèle vient de l'environnement, donc aucune ligne de code ne peut empêcher
cette bascule — seule la discipline de configuration le peut.

⚠️ La page **Privacy visible dans la navigation gouverne Vibe, pas l'API**. Les
deux jeux de bascules sont indépendants, et l'URL `/api/privacy` n'existe pas :
c'est `/plateforme/privacy`.

Mistral reste donc le meilleur candidat — mais **au prix de deux actions
explicites à faire et à vérifier**, pas par défaut.

### Quels modèles sont réellement accordés

Mesuré en appelant l'API le 2026-09-20. La page **Limits** de la console liste
tout le catalogue de la plateforme ; elle ne dit **pas** ce que votre
organisation obtient réellement.

| Modèle | Réponse | Débit accordé |
|---|---|---|
| `ministral-3b-2512` | 200 | 750 req/min |
| **`ministral-8b-2512`** | 200 | **188 req/min** — retenu |
| `ministral-14b-2512` | 200 | 30 req/min |
| `mistral-small-2603` | 429 | **0** |
| `mistral-medium-latest` | 429 | **0** |
| `mistral-large-2512` | 403 | — |

**Seule la famille Ministral est accordée.** Et `mistral-small-latest`, l'alias
qu'on écrit spontanément, n'existe même pas au catalogue de l'organisation.

Les deux modes d'échec se distinguent, et aucun ne dit « modèle inconnu » :

- **403** — modèle non autorisé pour cette organisation ;
- **429 avec `x-ratelimit-limit-req-minute: 0`** — présent au catalogue, mais
  sans quota.

Le second se lit comme un problème de compte. Il a coûté un après-midi à
diagnostiquer avant qu'on pense à changer le nom du modèle. **Devant un 429,
lire l'en-tête `x-ratelimit-limit-req-minute` avant de soupçonner le plan.**

La **vision fonctionne sur les trois Ministral**, ce qu'exige `/diagnose` —
vérifié avec une vraie image en URI de données.

Corollaire : le débit dépend du **modèle**, pas du compte. Changer
`MISTRAL_MODEL` impose de revoir `MISTRAL_RPS`, sinon la porte d'étranglement
protège contre la mauvaise limite.

### Les trois qui n'entraînent pas, sans rien avoir à faire

| Fournisseur | Engagement | Nuance |
|---|---|---|
| **Groq** | interdiction contractuelle d'utiliser les entrées et sorties pour entraîner ou affiner, **sans distinction gratuit/payant** | données en compartiments GCP **aux États-Unis** ; conservation 30 j pour abus, option « zéro rétention » |
| **Cloudflare Workers AI** | *« Cloudflare does not use your Customer Content to (1) train any AI models made available on Workers AI or (2) improve any Cloudflare or third-party services »* | **déjà sous-traitant du projet** (R2, CDN, WAF) |
| **Cerebras** | aucun droit d'entraînement sur le contenu, pas de conservation des entrées/sorties | centres de données **américains** ; offre surtout du texte, donc `/chat` seulement |

### À écarter en l'état

**OpenRouter** : la plateforme elle-même n'entraîne pas, mais elle ne fait que
router. Sa propre documentation prévient que **la plupart des points d'accès
gratuits entraînent sur les invites reçues, voire les publient**. Utilisable
seulement en restreignant le routage aux fournisseurs « zéro rétention ».

**GitHub** : depuis avril 2026, les interactions Copilot des paliers Free, Pro et
Pro+ servent à l'entraînement par défaut, opt-out possible. Cela vise Copilot ;
le régime de GitHub Models n'a pas été vérifié ici et ne doit pas être déduit du
précédent.

### Ce que ça donne pour Arbore

Deux familles de réponses, et elles ne coûtent pas la même chose :

1. **Rester hors UE mais sans entraînement** — Groq ou Cloudflare. Rien à
   activer, mais le transfert hors UE demeure, avec les clauses contractuelles
   types que la politique décrit déjà.
2. **Rester en UE** — Mistral, avec la bascule désactivée. Supprime le transfert
   hors UE pour ces deux routes, au prix d'une configuration à maintenir et à
   revérifier.

Dans tous les cas, **le palier gratuit de Gemini est le seul de la liste dont
les conditions demandent explicitement de ne pas envoyer de données
personnelles**.

## Ce que le code devrait apprendre à faire

Trois évolutions distinctes, dans l'ordre où elles se tiennent :

1. **Distinguer la finalité.** Ajouter un champ de purpose à `LLMRequest` (ou un
   paramètre à `generateLLM`) pour que `/chat` et `/diagnose` puissent viser des
   modèles différents. C'est le préalable aux deux autres, et c'est petit.

2. **Rendre la sélection dynamique.** `activeLLMProvider` devient un registre de
   fournisseurs plutôt qu'une variable unique, avec un ordre de préférence par
   finalité.

3. **Basculer sur épuisement.** Sur `429` ou sur quota local dépassé, essayer le
   fournisseur suivant de la liste. Demande de savoir reconnaître un refus pour
   quota — chaque API le signale à sa façon — et d'éviter de réessayer en boucle.

## Une clé par utilisateur ?

L'idée : chaque utilisateur fournit sa propre clé, consomme son propre quota
gratuit, et la clé partagée du projet disparaît.

Techniquement c'est faisable — `GeminiProvider` porte déjà sa clé en champ, il
suffirait de la prendre par requête. Mais trois obstacles décident avant la
technique :

- **Les conditions d'utilisation.** Une clé personnelle est délivrée à une
  personne pour son propre usage. La faire consommer par une application tierce
  sort du cadre chez certains fournisseurs. **À vérifier fournisseur par
  fournisseur avant tout développement.**
- **L'expérience.** Demander à un jardinier de créer un compte Google AI Studio
  et de coller une clé, c'est perdre l'essentiel des utilisateurs sur une
  fonctionnalité secondaire.
- **Le stockage.** Une clé personnelle est un secret : trousseau iOS côté
  appareil, jamais la base, jamais les journaux — et une nouvelle catégorie à
  déclarer dans la confidentialité.

Une piste intermédiaire tient la route : clé partagée par défaut avec les quotas
actuels, et clé personnelle **optionnelle** pour qui veut lever ses limites.
Cela suppose les trois évolutions ci-dessus.

## Voir aussi

- [`observability.md`](observability.md) — ce qui est journalisé côté backend
- [`securite-avant-publication.md`](securite-avant-publication.md) — gestion des secrets
