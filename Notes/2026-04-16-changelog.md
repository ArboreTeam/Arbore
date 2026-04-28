# Changelog — 15-16 avril 2026

## Plant3DGenerator (nouvel outil Python)

- Création d'un pipeline complet pour générer des modèles 3D de plantes via l'API Meshy AI
- Interface web locale (Flask, port 5555) avec boutons Preview / Refine / Generate All
- Fichier `input.txt` avec 30 plantes décoratives (nom FR, nom latin, hint visuel)
- Batch generation avec rate-limit retry (429 backoff automatique)
- Patch automatique `subdivisionScheme=none` sur chaque USDZ pour compatibilité iOS USD parser
- 30 modèles USDZ générés et déployés dans `ArboreBackend/models/`

## Mistral AI — alternative gratuite à OpenAI

- Refactor du microservice `AiGenerator` pour supporter Mistral Small comme provider
- Switch via env var `AI_PROVIDER=mistral` (défaut) / `openai`
- Même prompt système, même JSON mode, même response format — transparent pour le backend Go
- Les 29 nouvelles plantes générées gratuitement via le plan Experiment de Mistral
- Endpoint `/health` affiche maintenant le provider et modèle actifs

## Backend Go

- Champ `Generated *bool` sur Plant (flag "modèle 3D généré par IA")
- Champ `UpAxis *string` sur Plant ("Y" ou "Z" pour les exports Blender)
- Rebuild + redeploy Docker sur le VPS
- 38 thumbnails PNG pré-rendus (512x640, ~300 KB chacun) uploadés dans `/models/thumbnails/`

## MongoDB

- 29 nouvelles plantes insérées avec traductions FR/EN/ES/DE complètes
- Sansevieria + Monstera marqués `generated: true`
- 3 plantes Blender marquées `upAxis: "Z"` (Alocasia, Philodendron, Chamaedorea)
- Images Unsplash backfillées pour les 40 plantes (3 photos par plante)
- QA botanique : 17 plantes corrigées (erreurs factuelles, alias inventés, types de plante, toxicité Nandina)
- Fix array→string sur 9 plantes (Mistral retournait des arrays au lieu de strings pour certains champs)

## iOS — Catalogue

- Badge BETA vert (brandPrimary) sur les cards catalogue pour les plantes IA
- Champ `generated: Bool?` et `upAxis: String?` dans le modèle Plant Swift
- Thumbnails servis depuis le backend en PNG (plus de rendu 3D local pour le catalogue)
- Le renderer local reste en fallback si le backend est injoignable
- Cache thumbnail offline fonctionnel (PlantThumbnailCache)

## iOS — Thumbnail Renderer (réécriture complète)

- Suppression du per-plant height tuning hardcodé
- Auto-frame camera basé sur les bounds natives du USDZ (même échelle qu'en AR)
- FOV 35° telephoto + pitch 8° plongeant pour un rendu studio naturel
- Backdrop (sol + mur) dimensionné depuis le frustum caméra — plus de bords visibles
- Rotation Z-up lue depuis `plant.upAxis` (DB) au lieu d'une whitelist hardcodée
- Fix wall texture (`localizable: true` empêchait le chargement)

## iOS — AR Garden

- Fix threading crash : `arView.bounds` accédé depuis le SceneKit render queue → `cachedViewCenter` sur main thread
- Suppression du `dumpNodeTree()` appelé à chaque frame (~60fps log spam)
- `forceDownload: true` → `false` sur la pré-sélection de plante (utilise le cache)
- Propagation `upAxis` dans `placeObject` + `PersistedPlant` (couplage faible)
- Wrapper SCNNode pour la rotation Z-up sans interférer avec le transform AR

## iOS — Relocalization jardin

- Attente de `worldMappingStatus == .mapped` avant de restaurer les plantes
- Overlay de relocalisation animé (leaf pulse + texte localisé FR/EN/ES/DE)
- Guard `didRestoreGarden` pour empêcher les loads multiples
- Fix boucle de recréation SwiftUI (state modifié dans `makeUIView` → déplacé dans `.onAppear`)

## iOS — Réseau

- URLSession dédiée avec timeout 10s (vs 60s par défaut)
- Retry automatique sur timeout/connexion perdue (dodge iCloud Private Relay)

## iOS — Profil

- Personal Details : `"Hugo Michel"` hardcodé → lecture depuis Firebase Auth (displayName, email, phone)

## iOS — Warnings

- Tous les warnings build corrigés : APIs dépréciées (onChange, NavigationLink, Locale), actor isolation (Sendable, MainActor), variables inutilisées

## GitHub

- 12 issues créées (#84-#95), assignées Sprint 2, fermées comme résolues
- Issues #78 et #79 (Sprint 2 AR perf) fermées
- Version bump à 1.0
