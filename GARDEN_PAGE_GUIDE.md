# 🌱 Page du Jardin - Guide Rapide

## 📱 Interface Utilisateur

### Page Principale (NewMyGardenView)
```
┌─────────────────────────────────────┐
│  Mon Jardin                    [+]  │
│  Créez et gérez vos projets         │
├─────────────────────────────────────┤
│  📊 Statistiques Rapides            │
│  [3 Projets] [2 En cours] [1 Fini] │
├─────────────────────────────────────┤
│  📋 Liste des Projets               │
│  ┌───────────────────────────────┐  │
│  │ 🏡 Jardin Principal           │  │
│  │ Progression: ████████░░ 80%  │  │
│  │ [✓Scan] [✓Photos] [✓Infos]  │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 🌿 Balcon Fleuri             │  │
│  │ Progression: ████░░░░░░ 40%  │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### Page de Projet (GardenProjectDetailView)
```
┌─────────────────────────────────────┐
│  Jardin Principal            [⋮]   │
│  Étape 3 sur 7                      │
│  ████████████████░░░░ 80%          │
├─────────────────────────────────────┤
│  [Stepper Horizontal Scrollable]    │
│  ① ② ③→④ ⑤ ⑥ ⑦                    │
├─────────────────────────────────────┤
│  📋 Contenu de l'Étape Active       │
│                                     │
│  [Formulaires, Inputs, etc.]        │
│                                     │
├─────────────────────────────────────┤
│  [⬅ Précédent]     [Suivant ➡]     │
└─────────────────────────────────────┘
```

## 🎯 Les 7 Étapes du Projet

### 1️⃣ Scan du Jardin
```
📷 Scanner l'espace
├─ Type: Extérieur / Intérieur / Mixte
├─ Utilise l'appareil photo AR
├─ Mesure la surface (m²)
└─ Sauvegarde le fichier .usdz
```

### 2️⃣ Photos & Vidéos
```
📸 Médias du jardin
├─ Ajouter photos (multiple)
├─ Ajouter vidéos
├─ Suggestions: angles, lumière, eau
└─ Légendes optionnelles
```

### 3️⃣ Informations
```
ℹ️ Caractéristiques
├─ Type: ☑ Intérieur ☑ Extérieur
├─ Ensoleillement: Plein soleil / Mi-ombre / Ombre
├─ Type de sol: Argileux, Sableux, etc.
├─ Accès eau: Oui/Non
└─ Irrigation auto: Oui/Non
```

### 4️⃣ Localisation
```
📍 Position GPS
├─ Géolocalisation automatique
├─ OU sélection manuelle sur carte
├─ Détecte: Ville, Pays, Climat
└─ Zone de rusticité (hardiness zone)
```

### 5️⃣ Préférences
```
⚙️ Personnalisation
├─ Types de plantes (multi-sélection):
│   [Fleurs] [Arbustes] [Légumes] [Herbes]...
├─ Style: Moderne / Japonais / Méditerranéen...
├─ Densité: Épuré / Modéré / Dense
├─ Entretien: Très facile → Intensif
├─ Complexité: Débutant → Expert
├─ Budget: <100€ → Illimité
└─ Options: Enfants, Animaux, Comestible...
```

### 6️⃣ Zones de Plantation
```
🗺️ Dessiner les zones
├─ Affiche le scan 3D
├─ Dessiner avec le doigt
├─ Nommer chaque zone
├─ Définir le type de plante
└─ Ajouter des notes
```

### 7️⃣ Résumé
```
✅ Récapitulatif
├─ Score de complétude (%)
├─ Résumé de chaque étape
├─ Avertissement si incomplet
├─ Info sur l'analyse IA
└─ [✨ Analyser avec l'IA]
```

## 🎨 Palette de Couleurs

```
🟢 Vert    - Actions primaires, succès
🔵 Bleu    - Information, scan, localisation
🟠 Orange  - Avertissements, actions secondaires
🟣 Violet  - IA, analyse, zones
🔴 Rouge   - Erreurs, suppressions
🟡 Jaune   - Conseils, astuces
```

## 🔄 Flux de Données

```
User Input
    ↓
GardenProjectService
    ↓
GardenProject (Model)
    ↓
UserDefaults (JSON)
    ↓
[Future: Firebase]
```

## 🤖 Analyse IA (Future)

Lorsque l'utilisateur soumet le projet, l'IA va :

1. **Analyser le contexte**
   - Scan 3D + Zones dessinées
   - Photos/Vidéos
   - Climat + Localisation

2. **Respecter les contraintes**
   - Préférences utilisateur
   - Budget
   - Niveau d'entretien
   - Sécurité (enfants/animaux)

3. **Générer des recommandations**
   ```
   Pour chaque zone:
   ├─ 3-5 plantes suggérées
   ├─ Raisons du choix
   ├─ Disposition optimale
   ├─ Prix estimé
   └─ Calendrier de plantation
   ```

4. **Créer un plan d'action**
   ```
   📅 Calendrier
   ├─ Quand acheter
   ├─ Quand planter
   ├─ Entretien mensuel
   └─ Floraison attendue
   ```

## 📦 Structure des Fichiers

```
ArboreUi/
├── Models/
│   ├── GardenProject.swift          (Modèle principal)
│   └── GardenProjectService.swift   (Service CRUD)
├── Views/
│   ├── NewMyGardenView.swift        (Liste projets)
│   ├── GardenProjectDetailView.swift (Détail + Nav)
│   └── GardenSteps/
│       ├── ScanStepView.swift       (Étape 1)
│       ├── MediaStepView.swift      (Étape 2)
│       ├── InfoStepView.swift       (Étape 3)
│       ├── LocationStepView.swift   (Étape 4)
│       ├── PreferencesStepView.swift (Étape 5)
│       ├── ZonesStepView.swift      (Étape 6)
│       └── SummaryStepView.swift    (Étape 7)
└── Info.plist (avec permissions)
```

## 🚀 Fonctionnalités Clés

### ✅ Implémentées
- ✓ Création de projets multiples
- ✓ Navigation par étapes avec progression
- ✓ Intégration scan 3D (RoomScanner)
- ✓ Ajout photos/vidéos
- ✓ Formulaires d'informations complets
- ✓ Géolocalisation avec carte
- ✓ Préférences ultra-détaillées
- ✓ Dessin de zones sur canvas
- ✓ Résumé avec score de complétude
- ✓ Persistance locale (UserDefaults)
- ✓ Support mode sombre
- ✓ Animations et transitions

### 🔄 À Venir
- ⏳ Intégration API IA pour analyse
- ⏳ Affichage des recommandations IA
- ⏳ Vue 3D des zones sur le scan
- ⏳ Sauvegarde Firebase/Cloud
- ⏳ Partage de projets
- ⏳ Export PDF du plan
- ⏳ Notifications de rappel

## 💡 Cas d'Usage

### Exemple 1: Petit Balcon
```
1. Scan: Balcon 4m²
2. Photos: Exposition sud, rambarde
3. Info: Extérieur, Plein soleil, Accès eau
4. Lieu: Paris (Zone 8a)
5. Préfs: Style moderne, Entretien facile, Fleurs
6. Zones: 2 jardinières + 1 coin ombragé
7. IA suggère: Géraniums, Pétunias, Fougère
```

### Exemple 2: Grand Jardin
```
1. Scan: Jardin 150m²
2. Photos: Tour vidéo + détails
3. Info: Extérieur, Mi-ombre, Sol argileux
4. Lieu: Lyon (Zone 8b)
5. Préfs: Style cottage, Modéré, Mixte
6. Zones: 5 zones (potager, fleurs, arbustes, pelouse, terrasse)
7. IA crée un plan complet par zone
```

### Exemple 3: Appartement
```
1. Scan: Salon 25m²
2. Photos: Lumière par fenêtres
3. Info: Intérieur, Ombre, Chauffage central
4. Lieu: Marseille (Zone 9a)
5. Préfs: Style tropical, Très facile, Persistantes
6. Zones: Coin fenêtre + étagères + sol
7. IA suggère: Monstera, Pothos, Sansevieria
```

## 🎓 Guide pour les Développeurs

### Ajouter une nouvelle étape
```swift
// 1. Ajouter dans ProjectStep enum
case newStep = 8

// 2. Créer NewStepView.swift
struct NewStepView: View {
    let project: GardenProject
    @EnvironmentObject var projectService: GardenProjectService
    // ...
}

// 3. Ajouter dans GardenProjectDetailView
case .newStep:
    NewStepView(project: project)
```

### Modifier le modèle
```swift
// 1. Mettre à jour GardenProject.swift
struct GardenProject {
    var newField: NewType?
    // ...
}

// 2. Ajouter méthode dans GardenProjectService
func saveNewField(for projectId: String, field: NewType) {
    // ...
}

// 3. Utiliser dans la vue
projectService.saveNewField(for: project.id, field: value)
```

## 📞 Support

Pour toute question:
1. Consultez GARDEN_PAGE_DOCUMENTATION.md
2. Vérifiez les commentaires dans le code
3. Testez avec `add_garden_files.py`

Bon jardinage ! 🌻
