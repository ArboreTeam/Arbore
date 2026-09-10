# Observabilité (Sentry)

Reporting de crashs et de performance pour Arbore. **iOS**, **web** et **backend Go/Gin** sont câblés ; l'AiGenerator Python reste en **Phase 2**.

- Issue : #205
- SDK iOS : [`sentry-cocoa`](https://github.com/getsentry/sentry-cocoa) via Swift Package Manager
- SDK web : [`@sentry/nextjs`](https://github.com/getsentry/sentry-javascript)
- Org : `epi-apps` (sentry.io, résidence des données **UE**)
- Projets : `arbore-frontend` (iOS), `frontend-web-arbore` (web), `arbore-backend` (Gin)
- SDK backend : [`sentry-go`](https://github.com/getsentry/sentry-go) + `sentrygin`

---

## État mesuré — 2026-09-10

Relevé dans l'organisation Sentry, pas déduit de la configuration. À refaire
plutôt qu'à croire : ces chiffres vieillissent.

| projet | SDK | état |
|---|---|---|
| `arbore-frontend` (iOS) | ✅ | **remonte depuis le build 29** (régime anonyme, #495) |
| `frontend-web-arbore` | ✅ | 192 800 spans |
| `arbore-backend` | ✅ depuis #388 | panics, 5xx et échecs de démarrage |

### Ce que l'instrumentation a trouvé dès le premier jour

Le relevé du 2026-09-08 affichait « zéro erreur pour les trois projets ». Ce
n'était pas un signe de bonne santé, c'était la mesure de ce qui n'était pas
branché. Deux jours plus tard, les premiers événements réels ont livré trois
défauts qu'aucune relecture n'avait vus :

| événement | défaut | issue |
|---|---|---|
| `App Hanging: 2000 ms` | traits de plante recalculés à chaque appel, sur le fil principal | #499 |
| premier événement anonyme | `device_app_hash` quittait l'appareil sans consentement | #498 |
| le même, relu de plus près | `user.geo` portait pays **et ville**, sur un rapport anonyme | #498 |
| `App Hanging` au culprit `YourApp.$main` | c'était un runner XCTest, pas un utilisateur | #506 |
| — | questions du wizard sautables au doigt, trouvé en validant le même build | #500 |

Le second mérite d'être retenu : **l'anonymisation avait été déclarée conforme
après relecture, et la politique publique l'avait affirmée le lendemain.** C'est
l'événement réel qui a démenti les deux. Une relecture ne voit pas ce qu'un SDK
ajoute lui-même.

D'où la règle qui vaut maintenant pour ce projet : **vérifier sur un événement
réel après chaque build**, et n'écrire dans la politique que ce qui a été
observé sortir de l'appareil.

Une organisation Sentry `arbore` existe aussi, **vide**. Elle ne doit pas servir
de destination par erreur : tout vit dans `epi-apps`.

## iOS

| Élément | Emplacement |
|---|---|
| Wrapper SDK | `ArboreUi/ArboreUi/Observability/SentryManager.swift` |
| Init (avant Firebase) | `ArboreUi/ArboreUi/LoginAuth/AppDelegate.swift` |
| Config / assemblage DSN | `ArboreUi/ArboreUi/Config/AppConfig.swift` |
| Secrets (gitignorés) | `ArboreUi/Secrets.xcconfig` (+ `.example`) |
| Privacy manifest | `ArboreUi/ArboreUi/PrivacyInfo.xcprivacy` (CrashData + OtherDiagnosticData) |
| Upload dSYM | `fastlane/Fastfile` → lane `beta` |

`SentryManager` est **désactivé tant qu'un DSN n'est pas configuré**. Sans
secrets, l'app se build et tourne à l'identique (pratique pour les contributeurs
et la CI).

Il ne dépend en revanche **plus du consentement pour démarrer** (#469, #495).
Le raisonnement : un crash ne pouvait être observé que chez les utilisateurs
ayant activé un réglage qu'on ne leur proposait jamais, ce qui revenait à ne
rien observer. Deux régimes coexistent donc, et le consentement choisit lequel :

| | sans consentement | avec consentement |
|---|---|---|
| `user` (UID Firebase) | supprimé | conservé |
| `device_app_hash` | **retiré** (#498) | conservé |
| adresse IP | **remplacée par `0.0.0.0`** | **remplacée par `0.0.0.0`** |
| fils d'Ariane réseau | écartés | conservés |
| `tracesSampleRate` | `0` | `0.1` |
| `attachViewHierarchy` | non | oui |

Dans les deux régimes : ni IP, ni email, ni nom, ni corps de requête.

La logique vit dans deux fonctions pures, `scrub(_:consenti:)` et
`filtrer(_:consenti:)`, précisément pour être testable — elle était auparavant
enfouie dans une closure imbriquée, et c'est ce qui avait rendu #498 invisible
(#496). Neuf tests la couvrent, dont un éprouvé par neutralisation.

### La géolocalisation, et pourquoi le scrubbing n'y peut rien

Sentry dérive un pays **et une ville** de l'adresse IP, et les pose dans
`user.geo`. Ça se produisait y compris sur les rapports anonymes.

Le réglage « Prevent Storing of IP Addresses » ne suffit pas : il supprime
l'adresse, pas la position qui en a été tirée.

**Les règles de scrubbing non plus.** Mesuré le 2026-09-10, série de cinq
événements de contrôle :

| envoi | `user.geo` |
|---|---|
| aucune IP dans la charge | `FR, France` |
| aucune IP + règle `[Remove][Anything]` sur `$user.geo` | `FR, France` |
| aucune IP + règle sur `user.geo` (chemin, sans `$`) | `FR, Paris, France` |
| `user.ip_address: "0.0.0.0"` | **aucun bloc `user`** |
| `user.ip_address: "127.0.0.1"` | **aucun bloc `user`** |

Le troisième essai lève l'objection évidente — le pipeline ne tournerait pas :
sur ce même événement, `extra.password` et `extra.api_key` revenaient
`[Filtered]`. Le scrubbing marchait, les règles étaient actives, et elles ne
matchaient pas. La géolocalisation est calculée **après** l'étape de nettoyage :
le champ n'existe pas encore quand les règles s'appliquent.

**Ne pas reposer de règle sur `user.geo`.** Elle donnerait l'illusion d'une
protection.

**Ce qui marche** est côté client, dans `scrub()` : poser une adresse explicite
et non routable au lieu d'effacer le champ. Sentry n'essaie alors plus de
deviner. `0.0.0.0` est identique pour toutes les installations, donc rien
d'identifiant n'est réintroduit en échange.

C'est contre-intuitif et ça vaut d'être retenu : **effacer une donnée peut en
révéler une autre**, quand l'effacement rend la main à celui qui sait deviner.

`app_id` reste envoyé dans les deux régimes : c'est l'**UUID du binaire**,
identique pour toutes les installations d'un même build, et la symbolication en
dépend. Il ne désigne personne — contrairement à `device_app_hash`, qui est
propre à l'installation.

Autres options posées : `environment` (`debug` / `production`, cf. la section
suivante), `releaseName = version+build`, `dist = build`, `attachScreenshot =
false` (vie privée), `sendDefaultPii = false`.

### Setup iOS (one-shot)

**1. DSN → `Secrets.xcconfig`.** Le DSN est une URL `https://<publicKey>@<host>/<projectID>`. Comme un fichier xcconfig traite `//` comme un commentaire, il est stocké en **trois champs** réassemblés dans `AppConfig.sentryDSN` :

```
# Secrets.xcconfig (gitignoré — ne jamais committer)
SENTRY_DSN_PUBLIC_KEY = <public key>
SENTRY_DSN_HOST       = o<org>.ingest.de.sentry.io   # .de = UE
SENTRY_DSN_PROJECT_ID = <project id>
```

Laisser vide pour garder Sentry désactivé.

**2. Symbolication dSYM (fastlane).** La lane `beta` uploade les dSYM après l'upload TestFlight. Org/projet sont déjà câblés dans le Fastfile (`epi-apps` / `arbore-frontend`) ; il ne reste qu'à fournir un token d'auth. Sans token, la lane log un skip et continue.

```bash
brew install getsentry/tools/sentry-cli
cp .sentryclirc.example .sentryclirc   # puis coller le token (gitignoré)
bundle exec fastlane beta
```

Créer le token sur `sentry.io → Settings → Auth Tokens` (scopes `project:releases` + `project:write`). À la place de `.sentryclirc`, exporter `SENTRY_AUTH_TOKEN` ; surcharger `SENTRY_ORG` / `SENTRY_PROJECT` via l'environnement si besoin.

### Vérifier (iOS)

1. Renseigner le DSN dans `Secrets.xcconfig`, lancer un build **Debug**.
2. Profil → **Debug Tools → « Send Sentry test event »** (visible en DEBUG uniquement).
3. L'événement apparaît dans `sentry.io → arbore-frontend → Issues` en quelques secondes, tagué `environment: debug`. **Sans consentement il ne porte aucun `user`** — l'UID Firebase n'y est joint que si « Rattacher les diagnostics à mon compte » est activé.
4. Pour des crashs **release** symbolisés, livrer un build `fastlane beta` avec le token ci-dessus, puis déclencher un crash sur le build TestFlight.

> ℹ️ **Les tests n'émettent rien.** `start()` sort immédiatement sous XCTest
> (#506). Avant ce correctif, toute machine dont le `Secrets.xcconfig` portait un
> DSN envoyait un faux « App Hanging » à chaque exécution de la suite — la pile
> était celle du runner qui démarre. Si un événement de test vous manque, c'est
> normal : utilisez le bouton de debug ci-dessus, pas `xcodebuild test`.

**Et la vérification qui compte vraiment** : après chaque build livré, ouvrir un
événement réel et lire son JSON brut — `user`, le contexte `app`, les fils
d'Ariane. C'est cette lecture, et non la CI, qui a trouvé #498. Les tests
garantissent que le code retire ce qu'on lui a demandé de retirer ; ils ne
diront jamais qu'il ne reste rien d'autre.

## ⚠️ Le vocabulaire des environnements n'est pas unifié

Les trois composants n'étiquettent pas leurs événements de la même façon. C'est
un défaut connu, pas un oubli, et il faut le savoir avant de construire une vue
ou une alerte filtrée par environnement.

| Composant | Valeurs émises | D'où elles viennent |
|---|---|---|
| Backend Go | `prod` / `dev` | `SENTRY_ENVIRONMENT`, dérivée d'`ARBORE_ENV` |
| Web (serveur, edge) | `prod` / `dev` | idem |
| Web (navigateur) | `production` | repli `NODE_ENV`, figé au build |
| iOS | `debug` / `production` | `#if DEBUG` dans `AppConfig.environment` |

**Deux conséquences pratiques.**

Une vue filtrant sur `production` ne verra ni le backend ni le web serveur, qui
émettent `prod`. Le web a d'ailleurs changé de valeur le 2026-09-09 : ses données
antérieures sont sous `production`, les suivantes sous `prod`.

Et surtout : **les builds iOS `Debug` et `Dev` remontent sous la même
étiquette**, `debug`, alors que `Debug` vise la **production** et `Dev` vise
`api-dev.arbore.app`. Deux backends différents sous un seul nom.

Ce n'est pas faute d'information. `AppConfig.baseURL` lit
`ARBORE_BACKEND_HOST` depuis l'`Info.plist`, alimenté par le xcconfig de la
configuration : l'app sait parfaitement quel backend elle vise. Le défaut est
que `AppConfig.environment` ne le regarde pas — elle se fonde sur `#if DEBUG`,
que `Dev` hérite de toute façon. **Mauvais critère, pas information manquante.**

Ce piège est désormais **armé pour de bon** : depuis le build 29, l'iOS remonte.
Un événement venu d'un build `Dev` est aujourd'hui indiscernable d'un événement
venu d'un build `Debug`, alors qu'ils visent deux backends différents.

---

## Web (Next.js)

`@sentry/nextjs` est câblé via trois configs qui **no-op sans DSN** (vie privée d'abord : `sendDefaultPii: false`, pas de Session Replay) :

| Fichier | Runtime | DSN |
|---|---|---|
| `web/sentry.client.config.ts` | navigateur | `NEXT_PUBLIC_SENTRY_DSN` |
| `web/sentry.server.config.ts` | serveur Node | `SENTRY_DSN` \|\| `NEXT_PUBLIC_SENTRY_DSN` |
| `web/sentry.edge.config.ts` | edge | idem serveur |

`web/instrumentation.ts` charge les configs serveur/edge selon `NEXT_RUNTIME`. `tracesSampleRate = 0.1`. Les frontières d'erreur `web/app/error.tsx` et `web/app/global-error.tsx` appellent `Sentry.captureException`. L'upload des source maps est opt-in via `SENTRY_ORG` / `SENTRY_PROJECT` / `SENTRY_AUTH_TOKEN` (non committés) ; absent, le build n'échoue pas.

### Bruit du healthcheck

Le healthcheck Docker interroge `web/app/health/route.ts` — une route dédiée,
et non `/`. Cette transaction est exclue du tracing par `ignoreTransactions:
['GET /health']` dans `sentry.server.config.ts`.

Avant cette séparation (#469), la sonde visait `/` et représentait **21 880
spans sur 22 060 en 7 jours — 99,2 %** du volume tracé, quand toutes les vraies
pages réunies en totalisaient 180. Le tracing ne décrivait pas l'usage du site
mais la sonde qui le surveille — le motif de #388 côté backend, transposé au web.

Une route dédiée plutôt qu'un filtre sur `GET /` : la racine est aussi la vraie
page d'accueil, la filtrer aurait masqué le trafic qu'on cherche à voir.

`force-dynamic` sur la route est nécessaire — sans lui Next.js la prérendrait,
et la sonde ne testerait plus que la capacité à servir un fichier statique.

### Étiquetage des environnements

`SENTRY_ENVIRONMENT` (`prod` / `dev`, dérivée d'`ARBORE_ENV`) est lue **au
runtime** par `sentry.server.config.ts` et `sentry.edge.config.ts`. Une seule
image sert donc les deux environnements, chacun s'étiquetant lui-même.

Le piège corrigé par #469 : `NEXT_PUBLIC_SENTRY_ENV` est inlinée **à la
compilation**. La poser sur le conteneur n'avait aucun effet, `web/.env` la
laissait vide, et le repli `NODE_ENV` donnait `production` partout — prod et dev
indistinguables.

> ⚠️ **Limite restante, côté navigateur uniquement.** `sentry.client.config.ts`
> s'exécute dans le navigateur et ne peut pas lire une variable au runtime : son
> étiquette reste figée à la compilation. Sans effet aujourd'hui — sur 90 jours
> le projet n'a reçu **aucune** transaction de navigateur, tout le volume vient
> du serveur. Y remédier exigerait une image par environnement.

## Backend (Go)

`sentry-go` + `sentrygin`, câblés dans `ArboreBackend/observability.go` (#388). **No-op sans DSN**, comme iOS et web : l'absence de secret n'empêche jamais le backend de démarrer.

| Ce qui est capturé | Par quoi |
|---|---|
| Panics | `sentrygin` avec `Repanic: true` |
| Réponses 5xx délibérées | `captureServerErrors()` |
| Échecs de **démarrage** | `fatalf()` — voir ci-dessous |

**L'ordre des middlewares n'est pas arbitraire.** `sentrygin` est monté APRÈS `gin.Recovery()`, donc Recovery est le gestionnaire extérieur : sentrygin capture le panic et le relance, Recovery le rattrape et répond 500. Monté à l'envers, Sentry avalerait le panic et le client verrait une connexion coupée.

**Panics et 5xx ne se dupliquent pas**, bien que les deux mécanismes coexistent : un panic remonte la pile et fait sauter tout ce qui suit `c.Next()`. `captureServerErrors` ne s'exécute donc jamais pour un 500 issu d'un panic.

**`fatalf` remplace `log.Fatalf` au démarrage.** `log.Fatalf` appelle `os.Exit`, qui n'exécute aucun `defer` : un `defer flushSentry()` ne couvre pas les échecs d'initialisation. Or un backend qui refuse de démarrer est le cas le plus grave et le plus silencieux — le conteneur boucle, aucune requête n'arrive, le middleware ne voit rien.

**`SendDefaultPII` est à `false`, et doit le rester.** `true` joindrait l'adresse IP complète et les en-têtes aux événements, ce qui annulerait la troncature en `/24` introduite par [#385](https://github.com/ArboreTeam/Arbore/issues/385).

**Un seul projet, étiqueté par environnement.** `SENTRY_ENVIRONMENT` vaut `prod` ou `dev` et vient de `ARBORE_ENV`. Sentry filtre nativement dessus ; deux projets doubleraient les règles d'alerte pour une séparation que l'étiquette fournit déjà.

> ⚠️ La variable de source s'appelle **`SENTRY_DSN_BACKEND`**, pas `SENTRY_DSN` : le service web lit ce dernier, et un nom partagé enverrait ses erreurs serveur dans le projet du backend. Un DSN par service, donc une variable par service.

### Journal d'accès

Le routeur est construit par `newRouterEngine()` (`ArboreBackend/httplogging.go`) et **non** par `gin.Default()`. Même composition — `Logger` + `Recovery` — avec deux différences :

| | Comportement | Raison |
|---|---|---|
| **IP tronquée** | `/24` en IPv4 (`92.184.105.x`), `/48` en IPv6 (`2a01:e0a:1b2:x`), `-` si non parsable | `TrustedPlatform = "X-Real-IP"` fait résoudre l'IP réelle de l'utilisateur final : c'est une donnée personnelle (CJUE *Breyer*, C-582/14). Cf. [#385](https://github.com/ArboreTeam/Arbore/issues/385) |
| **`/health` exclu** | aucune ligne produite | Le healthcheck Docker représentait **95 %** du journal (233 lignes sur 244, mesuré le 2026-09-02) et noyait le trafic exploitable. Cf. [#388](https://github.com/ArboreTeam/Arbore/issues/388) |

L'IP **complète** reste utilisée par le rate limiter, mais uniquement **en mémoire**, dans un compteur purgé à l'expiration de la fenêtre (`WindowLimiter.purgeExpired`) : rien n'en est persisté. C'est le rate limiter qui constitue la défense active, pas le journal.

Pour une enquête nécessitant l'IP complète, la source est **Cloudflare**, qui la conserve en bordure.

### Rotation

`docker-compose.yml` fixe `max-size: 10m` / `max-file: 3` sur les trois services. Sans cette configuration, le driver `json-file` croît sans limite : les journaux ne disparaissaient qu'à la recréation d'un conteneur, ce qui n'est pas une politique de conservation (RGPD art. 5(1)(e)).

Au débit observé (~500 Ko/jour côté backend), 30 Mo représentent environ **deux mois** — et depuis l'exclusion de `/health`, ces 30 Mo ne contiennent plus que du trafic ayant une valeur d'analyse.

### Où chercher quoi

| Besoin | Aujourd'hui |
|---|---|
| Crash / panic | `sudo docker logs arbore-backend` — **fenêtre de rotation uniquement** |
| Erreur 5xx | idem |
| Trafic, 429 du rate limiter | journal d'accès, IP tronquée |
| Commit déployé | `curl localhost:8080/health` → champ `commit` ([#341](https://github.com/ArboreTeam/Arbore/issues/341)) |
| IP complète d'un incident | journaux Cloudflare |

## Notes / suites

- Le pont breadcrumbs depuis l'`AppLog` de l'app iOS (nav / session AR / sauvegarde jardin) est un nice-to-have pas encore câblé.
- Le backend est instrumenté depuis #388. Reste l'**AiGenerator** (`sentry-python`), non câblé : ses erreurs ne survivent toujours pas à la rotation des journaux Docker.
- Couverture partielle assumée côté 5xx : un handler qui répond 500 produit un événement synthétique (route + statut) faute d'erreur déclarée — le code compte 40 réponses 500 pour 2 appels à `c.Error(...)`. Enrichir suppose que les handlers déclarent leurs erreurs, ce qui est un chantier de fond.
- Session Replay est une fonctionnalité payante — non utilisée.
