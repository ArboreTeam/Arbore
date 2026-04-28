# 🔍 Guide Diagnostic : Chamaedorea_Elegans ne s'affiche pas

## Étape 1 : Vérifier les logs du renderer

Quand tu génères la thumbnail, **regarde la console Xcode** (Xcode → View → Debug Area → Show Console).

Tu veras un output comme :
```
═══════════════════════════════════════════
🌿 Thumbnail modelKey: Chamaedorea_Elegans
   → normalized: chamaedorea_elegans
   → targetHeight: 0.016
   → original bounds: BoundingBox(min: [-0.1, 0.0, -0.1], max: [0.1, 0.5, 0.1])
   → original height (extents.y): 0.5
   → scale factor: 0.032
   → final position: SIMD3<Float>(-0.0, 0.0, 0.0)
   → CHECKING MATERIALS...
   → materials.count: 2
      Material 0: PhysicallyBasedMaterial
      Material 1: PhysicallyBasedMaterial
═══════════════════════════════════════════
```

---

## ⚠️ Signes d'alerte

### Signe 1 : Bounds presque nuls
```
⚠️  WARNING: Model bounds are too small!
   extents: SIMD3<Float>(0.0001, 0.0001, 0.0001)
```
**Cause** : Le fichier `.usdz` est vide ou corrompu  
**Solution** : Remplace le fichier `Chamaedorea_Elegans.usdz`

### Signe 2 : Scale factor énorme
```
   → scale factor: 1000.0
```
**Cause** : Les bounds originaux sont minuscules → l'échelle explose → modèle sort du champ  
**Solution** : Réexporte le `.usdz` à l'échelle correcte

### Signe 3 : NO MODEL COMPONENT !
```
   ⚠️  NO MODEL COMPONENT!
```
**Cause** : Le `.usdz` n'a pas de géométrie valide  
**Solution** : Le fichier est corrompu

### Signe 4 : Matériaux transparents
```
   → materials.count: 1
      Material 0: UnlitMaterial(color: white, opacity: 0.0)
```
**Cause** : Opacity = 0 → le modèle est invisible  
**Solution** : Exporte avec matériaux opaques

---

## 🛠️ Tests à faire

### Test 1 : Vérifier l'intégrité du fichier USDZ

**Via Terminal** :
```bash
cd ArboreBackend/models
file Chamaedorea_Elegans.usdz
unzip -l Chamaedorea_Elegans.usdz | head -20
```

Devrait afficher une liste de fichiers. Si rien ou erreur → fichier corrompu.

### Test 2 : Ouvrir le USDZ dans Xcode

1. Xcode → File → Open
2. Sélectionne `Chamaedorea_Elegans.usdz`
3. Appuie sur Space pour preview
4. Si tu vois le modèle 3D → fichier OK

### Test 3 : Vérifier les logs de chargement

Cherche dans les logs :
```
❌ Render error: ...
```

Si tu vois une erreur, elle te dira exactement ce qui s'est passé.

---

## 📊 Checklist de débogage

```
☐ Chamaedorea_Elegans.usdz existe dans ArboreBackend/models/
☐ Le fichier n'est pas vide (file size > 100KB)
☐ Il se prévisualise dans Xcode
☐ Les logs du renderer montrent bounds valides (> 0.01)
☐ Scale factor raisonnable (< 100)
☐ Materials.count > 0 (il y a de la géométrie)
☐ Pas d'erreur "Render error" dans les logs
```

---

## 🔧 Solution rapide

Si tu vois un message d'erreur dans les logs, teste ceci:

**Comparaison avec un modèle qui marche** :
```bash
# Compare les tailles de fichiers
ls -lh ArboreBackend/models/*.usdz
```

Exemple de sizes normales:
- `Pothos.usdz` : 2.0 MB
- `Cactus.usdz` : 3.3 MB
- `Chamaedorea_Elegans.usdz` : ?

Si Chamaedorea est beaucoup plus petit (ex. < 100KB) → **corrompu**

---

## 🐛 À chercher dans les logs

Quand tu génères les thumbnails, copie-colle les logs de cette plante ici:

```
🌿 Thumbnail modelKey: Chamaedorea_Elegans
   → [LEG COLLE LES AUTRES LOGS ICI]
```

Je pourrai te dire exactement quel est le problème!
