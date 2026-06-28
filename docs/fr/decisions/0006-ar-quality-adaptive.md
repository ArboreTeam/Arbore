# ADR 0006 — Stratégie adaptative de qualité AR (`environmentTexturing` + thermal observer)

- **Statut** : Accepted
- **Date** : 2026-05-12
- **Décideurs** : Équipe Arbore

## Contexte

Le mode `ARWorldTrackingConfiguration.environmentTexturing = .automatic` retient en mémoire un cube map HDR mis à jour en continu depuis le flux caméra. Coût mémoire : 50 à 100 MB par session active, plus quelques millisecondes de temps GPU par frame sur A15. Bénéfice : reflets réalistes sur les matériaux spéculaires (céramique des pots, métal, verre).

Pour l'usage Arbore (plantes principalement mates, scènes intérieures ou jardins), le bénéfice visuel est faible et le coût mémoire non-négligeable — l'app frôle régulièrement le seuil de jetsam iOS sur les devices à 3 GB de RAM (iPhone XR).

Apple recommande dans ses talks WWDC (« Designing for Adverse Network and Temperature Conditions », WWDC19) de **dégrader proactivement les options graphiques coûteuses** quand `ProcessInfo.thermalState` se dégrade. Le mode `.automatic` d'ARKit gère la *couverture caméra* mais **n'est pas thermal-aware**.

Deux issues sources ont été consolidées : #80 (config `environmentTexturing`) et #82 (observer thermal state).

## Décision

Un module dédié `ArboreUi/ArboreUi/ARGarden/Quality/` regroupe la stratégie adaptative. Quatre composants en couplage faible :

| Fichier | Responsabilité |
|---|---|
| `DeviceCapabilities.swift` | Détecte le tier du device via `ProcessInfo.physicalMemory` (seuil 4 GB). Aucune dépendance ARKit. Pas de hardcoded model strings. |
| `ARQuality.swift` | Enum `full / standard / lite`. `static var recommended` lit `DeviceCapabilities.tier` + `ProcessInfo.thermalState` pour décider du niveau retenu. Expose `environmentTexturing: ARWorldTrackingConfiguration.EnvironmentTexturing`. |
| `ARQualityObserver.swift` | Singleton, écoute `ProcessInfo.thermalStateDidChangeNotification` au long de la vie de l'app. Republie des notifications métier `.arboreThermalCritical` et `.arboreThermalRecovered`. Démarré depuis `AppDelegate.didFinishLaunchingWithOptions`. |
| `ThermalStateBanner.swift` | Overlay SwiftUI dismissable, s'abonne aux notifications métier. Attaché en `overlay(alignment: .top)` sur `GardenARPlacementView`. |

Les six sites qui posaient `config.environmentTexturing = .automatic` consomment désormais `ARQuality.recommended.environmentTexturing`.

`ARQuality.recommended` est **figé pour toute la durée d'une session AR**. Changer `environmentTexturing` mid-session demanderait `session.run(config, options: [.resetTracking])` qui invaliderait la `ARWorldMap` relocalisée — sacrifice trop coûteux pour un utilisateur qui vient de scanner son jardin. Les dégradations dynamiques sous pression thermique passent uniquement par le banner UI à ce stade.

## Conséquences

### Positives

- Sur device legacy (< 4 GB RAM) ou en condition thermique tendue (`.serious`/`.critical`), `environmentTexturing` retombe automatiquement sur `.none`, ce qui libère 50-100 MB de RAM dès le démarrage de la session AR.
- L'utilisateur reçoit un feedback visuel explicite (banner) quand le système rapporte une pression thermique critique, plutôt qu'un ralentissement silencieux dû au throttling iOS.
- L'architecture isole la décision dans un module unique, testable indépendamment. Aucun appelant n'a à lire `ProcessInfo.thermalState` ni à connaître la table des devices.
- L'observer global vit dans `ARQualityObserver` une seule fois (singleton), tous les composants UI partagent les mêmes notifications.

### Négatives

- Sur un device dégradé temporairement (`.fair` au démarrage, retour à `.nominal` après quelques minutes), `ARQuality` aura figé `.standard` pour la session entière alors qu'Apple aurait éventuellement laissé tourner `.automatic`. C'est une légère sur-prudence assumée.
- Six sites de configuration AR ont été modifiés, ce qui couple ces vues au module `ARGarden/Quality/`. Le couplage est en lecture seule (`ARQuality.recommended.environmentTexturing`) donc reste lâche, mais une migration future devrait penser à mettre à jour tous les sites.
- L'utilisateur sans préférence ne peut pas forcer `.lite` pour économiser la batterie. Cas couvert par l'[issue #150](https://github.com/ArboreTeam/Arbore/issues/150) (toggle Settings, hors MVP).

### Neutres

- Le seuil 4 GB est aligné sur la limite pratique observée pour un usage AR multi-objets avec textures PBR. Il pourra évoluer dans un ADR de successeur si les retours utilisateurs montrent une autre frontière.
- Les notifications métier (`.arboreThermalCritical` et `.arboreThermalRecovered`) sont plus stables dans le temps que la notification système et permettent une politique de seuils unique centralisée dans `ARQualityObserver`.

## Alternatives considérées

- **Ne rien changer, laisser `.automatic` partout** — écarté car le throttling silencieux iOS produit des dégradations subtiles non explicables à l'utilisateur. Apple recommande explicitement d'observer le thermal state.
- **Désactiver `environmentTexturing` partout (`.none` forcé)** — écarté car les iPhone 12+ avec 4+ GB de RAM peuvent largement encaisser le coût et bénéficient visuellement des reflets.
- **Changer `environmentTexturing` dynamiquement pendant la session** — écarté à cause de la perte de relocalisation `ARWorldMap` qu'imposerait un `resetTracking`. L'utilisateur perdrait sa session de scan en cours.
- **Hardcoder une table de modèles d'iPhone** (XS, XR, 11, 12, …) — écarté car la table devrait être maintenue à chaque nouvelle génération. `ProcessInfo.physicalMemory` est un proxy stable, déclaratif et future-proof.
- **Exposer immédiatement le toggle Settings « Mode économie batterie »** — écarté pour le MVP afin de garder la logique entièrement automatique. Le toggle est suivi par l'issue #150 et reposera sur un `UserDefaults` lu en début de `ARQuality.recommended`.

## Liens

- [Issue #80 — Passer environmentTexturing de `.automatic` à `.none`](https://github.com/ArboreTeam/Arbore/issues/80)
- [Issue #82 — Observer le thermal state et dégrader la qualité AR](https://github.com/ArboreTeam/Arbore/issues/82)
- [Issue #150 — Toggle Settings « Mode économie batterie »](https://github.com/ArboreTeam/Arbore/issues/150)
- [PR #151 — Implémentation initiale du module `ARGarden/Quality/`](https://github.com/ArboreTeam/Arbore/pull/151)
- [WWDC19 — Designing for Adverse Network and Temperature Conditions](https://developer.apple.com/videos/play/wwdc2019/422/)
- [Apple — `ProcessInfo.ThermalState`](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum)
