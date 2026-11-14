# Ce que les CGU promettent, et ce qui le tient

Depuis la **version 2.3** des conditions générales, Arbore n'affirme plus
seulement qu'il décline sa responsabilité : il **décrit son propre
comportement**. Trois clauses disent comment l'app se conduit, et une
quatrième s'engage sur une date.

Ces phrases ne sont vraies que parce que du code se comporte d'une certaine
façon et que des éléments d'interface sont affichés. Retirer l'un d'eux rend le
contrat faux — et **aucun test ne tombera**.

Cette page est la liste de ces dépendances. Elle s'adresse à qui ajoute des
plantes au catalogue et à qui redessine un écran.

## Le tableau

| La clause dit | Ce qui le tient | Vérifié par |
|---|---|---|
| « les filtres de sécurité du foyer écartent ce qui est **connu** comme dangereux, pas ce qui n'a pas encore été établi » | `PlantCatalogContext.appendSafetyCriterion` : un verdict `nil` part dans `missing`, jamais dans `positive` | `PlantSafetyOutcomeTests` |
| « une plante dont la toxicité n'est pas établie est **signalée comme telle** » | `PlantCatalogView` rend `AR_CATALOG_MISSING_PET_TOXICITY` dans la section « Informations à confirmer », icône orange | **rien** |
| « l'absence de signalement ne vaut pas confirmation d'innocuité » | le vocabulaire fermé : `unknown` ne devient jamais `safe` (`Plant.swift`, décodage indulgent vers le plancher) | `PlantToxicityVerdictTests` |
| « chaque verdict est repris d'une base nommée et datée » (`TOXICITY_DISCLAIMER_BODY`) | `TOXICITY_SOURCE_AND_DATE` sous le verdict ; en base, `detail` et `evidence` vont ensemble | `ConsentDocumentVersionTests` (versions), `test_verser_toxicite` (versement) |
| « toute modification importante te sera signalée **avant son entrée en vigueur** » | `AppConfig.termsVersion` / `privacyPolicyVersion`, le registre `consents`, et `guestAcceptedDocuments` qui compare les versions | `ConsentDocumentVersionTests` |
| l'acceptation est un **acte**, pas un usage | `hasAcceptedDocuments` gouverne les trois chemins de compte ; `GuestAcceptanceSheet` gouverne l'entrée invité sur les deux écrans | **rien** |

Deux lignes portent **rien** dans la colonne de droite. Ce sont les deux que ce
document existe pour protéger : elles tiennent à un élément d'interface, et un
élément d'interface se retire sans bruit.

## Quand on ajoute des plantes

La règle de fond : **une valeur se transcrit, elle ne se déduit pas.** Voir
[`operations/botanical-data-audit.md`](operations/botanical-data-audit.md) pour
les critères d'acceptation, et
[`operations/chaine-plante.md`](operations/chaine-plante.md) pour le chemin.

Ce qui relève de cette page :

- **Pas de source nommée, pas de prose.** Le verdict peut être posé sans
  source — `toxic` et `unknown` n'affirment pas l'innocuité. Le détail, non :
  il est une formulation, et la servir sans dire d'où elle vient revient à
  reprendre une rédaction au lieu de citer un fait. `verser-toxicite.py` le
  refuse à la frontière. Voir
  [`operations/provenance-assets.md`](operations/provenance-assets.md).
- **`safe` sans source est refusé**, et doit le rester. C'est la seule valeur
  qui AFFIRME l'innocuité.
- **`unknown` n'est pas un défaut de remplissage.** Une fiche sans verdict est
  servie, signalée, et c'est le comportement voulu. Compléter à tout prix pour
  « faire propre » est exactement ce que la clause interdit.

## Quand on redessine

Trois éléments sont **porteurs de contrat**. Les déplacer est libre ; les
supprimer ne l'est pas.

**La section « Informations à confirmer » du catalogue AR.** C'est elle qui
rend vraie la phrase « signalée comme telle ». Une refonte qui la fond dans un
pied de page générique, ou qui la masque derrière un repli, retire le
signalement sans retirer la clause.

**La ligne de source sous chaque verdict.** « Source : X — consultée le Y » est
ce qui distingue un fait attribué d'une affirmation de l'app. Sans elle, les
CGU promettent une traçabilité que l'écran ne montre plus.

**La case d'acceptation.** Elle gouverne quatre chemins : inscription par
e-mail, Apple, Google, et l'entrée invité. Le dernier passe par
`ContinueAsGuestButton`, partagé entre l'écran de connexion et celui
d'inscription — c'est volontaire, une porte verrouillée d'un seul côté ne
verrouille rien.

> **Le piège du redesign : un nouveau point d'entrée.** Ajouter un bouton
> d'authentification — un autre fournisseur, un lien profond, un parcours
> d'essai — crée un chemin que la case ne gouverne pas. Rien ne le signalera.
> Tout nouveau point d'entrée doit passer par `hasAcceptedDocuments` ou par la
> feuille d'acceptation.

**Un arbitrage ouvert, à ne pas découvrir deux fois.** Sur l'écran de
connexion, Apple et Google peuvent créer un compte lors d'une première
connexion, sans case. Ils ne sont pas gouvernés : cet écran sert d'abord à
reconnecter des comptes existants, dont l'acceptation est déjà au registre, et
« première connexion » ne se distingue pas de « reconnexion » avant le fait.
C'est le dernier chemin de création sans acte positif, et il est connu.

## Si une clause change

Les conditions vivent à deux endroits : `terms.html` dans **Arbore_SiteVitrine**
est le document de référence, les chaînes `TERMS_*` de l'app le miroitent.

**Les deux montent en version ensemble.** Un document légal dont le contenu
change sans que sa version bouge n'est plus opposable — c'est le défaut relevé
en #822, et `AppConfig.termsVersion` existe pour que la version accompagne le
texte jusqu'au registre de consentement.

Changer une clause de ce tableau sans changer le code qu'elle décrit produit
une affirmation fausse dans un document contractuel. Dans ce sens-là non plus,
aucun test ne tombera.

## Voir aussi

- [`operations/provenance-assets.md`](operations/provenance-assets.md) — d'où viennent les données, et sous quel régime
- [`operations/botanical-data-audit.md`](operations/botanical-data-audit.md) — les critères d'acceptation d'une valeur
- [`screens/plant-catalog.md`](screens/plant-catalog.md) — l'écran qui porte le signalement
- [`flows/auth-signup.md`](flows/auth-signup.md) — les chemins de création de compte
