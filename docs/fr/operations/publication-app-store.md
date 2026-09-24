# Publier sur l'App Store

TestFlight et l'App Store sont deux circuits distincts qui partagent un seul
dépôt de builds. Cette page couvre le second ; le premier est dans
[`testflight-deploy.md`](testflight-deploy.md).

Écrite après la soumission de la **1.0.0 le 2026-09-24**, à partir de ce qui
s'est réellement passé.

## Ce qui s'automatise, et ce qui ne s'automatise pas

| Étape | Outil |
|---|---|
| Version commerciale, build, archive, upload | `fastlane public_beta` (ou `beta`) |
| Textes de la fiche, 4 langues, URLs, infos App Review | `fastlane upload_metadata` |
| Captures, 4 langues | `fastlane upload_screenshots` |
| Attacher la build à la version | ASC |
| **App Privacy** | ASC, à la main |
| Catégories, classification d'âge, Content Rights | ASC, à la main |
| Pricing and Availability | ASC, à la main |
| Mode de publication, puis « Add for Review » | ASC, à la main |

Les deux lanes de fiche poussent dans le **brouillon** de la version courante et
ne soumettent jamais rien. Elles lisent la version depuis le projet Xcode : une
version éditable doit donc exister dans ASC.

Il n'existe pas de lane `release` qui enchaînerait tout. C'est délibéré : le bon
moment pour l'écrire est après une **deuxième** soumission, quand la forme réelle
du cycle répétable sera connue.

## Les pièges, dans l'ordre où ils tombent

### `agvtool` casse le versionnement de ce projet

`Info.plist` référence `$(MARKETING_VERSION)` : une seule source de vérité, et
c'est le bon montage. `agvtool new-marketing-version` **fige la valeur en dur
dans le plist sans toucher au réglage de build** :

```diff
- <string>$(MARKETING_VERSION)</string>
+ <string>1.0.0</string>
```

Les deux se désaccordent alors silencieusement. Le binaire porte la nouvelle
version pendant que `get_version_number` lit encore l'ancienne, donc
`upload_metadata` et `upload_screenshots` remplissent la fiche de **la mauvaise
version**. On ne s'en aperçoit qu'en découvrant une fiche vide au moment de
soumettre.

**Passer par Xcode, ou éditer `MARKETING_VERSION` directement.** Les messages
`Cannot find ".../NO"` et `".../YES"` qu'affiche agvtool ici viennent du même
égarement : il cherche `INFOPLIST_FILE` et tombe sur les valeurs de
`GENERATE_INFOPLIST_FILE`.

### Le numéro de build repart à 1 sur une nouvelle version

`latest_testflight_build_number` interroge App Store Connect **pour une version
donnée**. Sur un train de version neuf, il ne trouve rien et rend 1 ; la lane
incrémente à 2. Après 37 builds en `0.1.12`, la première `1.0.0` porte donc le
numéro **2**.

C'est valide : Apple n'exige l'unicité et la croissance qu'**à l'intérieur** d'un
même train de version. Rien n'en dépend côté projet — Sentry nomme sa release
`<version>+<build>` et apparie les dSYM par UUID de débogage, et aucun code de
l'app ne compare de numéros.

### La Beta App Review passe de 5 minutes à ~20 heures

Apple n'examine réellement que la **première build d'une version donnée**. Les
suivantes du même `CFBundleShortVersionString` passent en voie rapide.

Mesuré : builds 24 à 37, toutes en `0.1.12`, approuvées en 1 à 5 minutes. La
`1.0.0 (2)`, premier build d'un train neuf, a demandé **19 h 42**.

À prévoir à chaque changement de version commerciale. Les testeurs **internes**,
eux, reçoivent la build sans attendre cette revue.

### `deliver` peut créer des doublons de captures

Il envoie tous les fichiers, puis vérifie leur présence. App Store Connect
indexant avec du retard, cette vérification signale parfois des fichiers
« missing » qui sont bel et bien montés. La reprise automatique les renvoie, et
ils **s'empilent au lieu de se remplacer**.

`overwrite_screenshots: true` n'en protège pas : il efface **avant** l'envoi, pas
pendant les reprises.

**Toujours recompter après un push** ; le « Successfully uploaded all
screenshots » ne suffit pas. Les doublons se suppriment par l'API ou dans Media
Manager.

### `copyright.txt` est global, et son absence bloque tout

`fastlane/metadata/copyright.txt`, à la racine de `metadata/` — pas un fichier
par langue, contrairement à la description, aux mots-clés et aux URLs. Format
attendu : l'année d'obtention des droits puis le titulaire, sans URL ni symbole.

Son absence ne se voit qu'au dernier écran, sur un « Unable to Add for Review ».

### Le slot de captures ouvert par défaut est le mauvais

La page de version ouvre sur le slot **6,5"**, qui attend `1242 × 2688` ou
`1284 × 2778`. Nos captures sont en `1290 × 2796`, soit le slot **6,9"** — le
seul requis depuis 2024.

Passer par **« View All Sizes in Media Manager »**. Une fois posées, ASC affiche
« 6.5" Display — Using 6.9" Display » : il n'y a donc pas lieu d'exporter la
taille de repli.

Penser aussi à changer le **sélecteur de langue**, qui ouvre sur le français.

### Pas d'iPad, pas de Mac, pas de Vision Pro

`TARGETED_DEVICE_FAMILY = 1` : aucune capture iPad ne sera jamais demandée.

Pour Mac et Vision Pro, ASC annonce « Version X is compatible », mais c'est un
test de compilation et non un jugement d'expérience. Arbore repose sur ARKit, la
caméra et le LiDAR : sans eux, la fonction centrale ne marche pas. Les deux cases
restent décochées.

## App Privacy

C'est le morceau le plus risqué, et aucun outil ne le pousse. Les réponses sont
rédigées dans [`../../appstore-listing.md`](../../appstore-listing.md), vérifiées
contre le code.

Trois choix y demandent un raisonnement, et se reperdraient :

- **`Coarse Location` est à déclarer**, en *App Functionality* **et** *Product
  Personalization*. La position arrondie modifie réellement la liste proposée :
  `PlantCatalogContext` en tire une exclusion dure avant classement.
- **`Environment Scanning` n'est PAS à déclarer**, malgré ARKit et le LiDAR. La
  définition d'Apple est « transmettre hors de l'appareil », et les WorldMaps
  comme les scènes restent dans le container de l'app.
- **Aucun suivi.** Ni `AdSupport`, ni `NSUserTrackingUsageDescription`, ni
  `FirebaseAnalytics` — seuls `FirebaseAuth`, `FirebaseCore` et
  `FirebaseFirestore` sont liés au binaire.

Une déclaration incohérente avec le comportement réel est un motif de rejet
fréquent. Le cas s'est produit : la localisation manquait alors que la
description de la fiche l'annonçait, sur la même page produit.

## Avant de soumettre

La publication peut être réglée sur **automatique** ou **manuelle**. En
automatique, Apple approuve quand il veut — y compris la nuit — et la fiche
devient publique dans la minute.

Dans les deux cas, vérifier que la production est prête :

```sh
curl -s -o /dev/null -w "%{http_code}\n" https://api.arbore.app/health
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://api.arbore.app/chat   # 401 attendu
curl -sL -o /dev/null -w "%{http_code}\n" https://arbore.app/privacy
```

## Voir aussi

- [`testflight-deploy.md`](testflight-deploy.md) — les lanes et le circuit TestFlight
- [`provenance-assets.md`](provenance-assets.md) — pour répondre à Content Rights
- [`../../appstore-listing.md`](../../appstore-listing.md) — textes et réponses App Privacy
