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

## Le point le plus important : le régime des données en palier gratuit

**À vérifier avant toute décision, et à re-vérifier régulièrement.**

Les conditions des API génératives distinguent presque toutes le palier gratuit
du palier payant sur un point qui n'est pas le prix : **l'usage des contenus
soumis**. Plusieurs fournisseurs, Google compris, se réservent en palier gratuit
le droit d'exploiter les contenus envoyés pour améliorer leurs produits, avec
relecture humaine possible ; le palier payant l'exclut.

Arbore transmet des **photos prises par l'utilisateur chez lui** et ses messages.
Si le palier gratuit emporte ce régime, alors :

- la politique de confidentialité doit le dire — elle annonce aujourd'hui une
  transmission « pour être analysés », ce qui ne couvre pas un entraînement ni
  une relecture humaine ;
- c'est un argument fort pour un fournisseur européen, ou pour un palier payant
  même symbolique.

Cette page ne tranche pas : elle signale que **la vérification conditionne tout
le reste**, y compris le choix des fournisseurs du tableau suivant.

## Catalogue des API gratuites

⚠️ **Les chiffres ci-dessous datent et doivent être revérifiés à la source avant
d'être codés en dur.** Les paliers gratuits changent sans préavis, parfois d'un
mois à l'autre, et varient selon la région. Ce tableau sert à choisir *qui
tester*, jamais à alimenter une constante.

Colonne « Vision » = capable de traiter une image, donc éligible à `/diagnose`.
Sans elle, un fournisseur ne peut servir que `/chat`.

| Fournisseur | Vision | Ordre de grandeur du palier gratuit | À vérifier en priorité |
|---|---|---|---|
| **Google Gemini** (AI Studio) | ✅ | quelques dizaines de requêtes/min, quelques centaines/jour selon le modèle | régime des données, disponibilité UE |
| **Mistral** (La Plateforme) | ✅ Pixtral | palier d'expérimentation, vérification téléphonique requise | **hébergement UE** — pas de transfert hors UE |
| **Groq** | ✅ Llama 4 | généreux en requêtes/jour, très rapide | politique d'entraînement, modèles vision disponibles |
| **Cerebras** | ❌ surtout texte | quota quotidien en tokens | couvre `/chat` seulement |
| **OpenRouter** | ✅ selon modèle | variantes `:free`, plafond bas sans crédit | quel modèle sous-jacent, et ses conditions |
| **Cloudflare Workers AI** | ✅ selon modèle | allocation quotidienne | déjà fournisseur du projet (R2, CDN) |
| **GitHub Models** | ✅ selon modèle | paliers liés au compte GitHub | usage en production autorisé ? |
| **Cohere** | ✅ Aya Vision | clé d'essai, plafond mensuel | usage commercial exclu du palier d'essai |

Deux remarques de sélection :

**Mistral mérite un examen à part.** C'est le seul de la liste dont
l'hébergement est européen. La politique de confidentialité gère aujourd'hui un
transfert hors UE avec clauses contractuelles types ; un fournisseur européen le
rendrait sans objet pour ces deux routes. Et `initLLMProvider()` l'attend déjà.

**Cloudflare est déjà un sous-traitant du projet** (R2, CDN, WAF). Ajouter une
route IA chez lui n'ajoute pas de sous-traitant à déclarer.

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
