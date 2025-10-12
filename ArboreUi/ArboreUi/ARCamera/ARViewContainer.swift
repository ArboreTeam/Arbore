import SwiftUI
import ARKit
import RealityKit

struct ARViewContainer: UIViewRepresentable {
    @Binding var arView: ARView
    let modelURL: URL

    func makeUIView(context: Context) -> ARView {
        let coordinator = context.coordinator
        coordinator.modelURL = modelURL

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config)

        // Add AR coaching overlay to guide plane detection
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = arView.session
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.goal = .anyPlane
        coachingOverlay.frame = arView.bounds
        arView.addSubview(coachingOverlay)

        // Gestures: double-tap (scale), single-tap (place/select), long-press (select), pan (move), pinch (scale)
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.require(toFail: doubleTapGesture)
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))

        longPressGesture.minimumPressDuration = 0.5

        arView.addGestureRecognizer(doubleTapGesture)
        arView.addGestureRecognizer(tapGesture)
        arView.addGestureRecognizer(longPressGesture)
        arView.addGestureRecognizer(panGesture)
        arView.addGestureRecognizer(pinchGesture)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject {
        // Store base scale and cycling mode for double-tap scaling
        struct ScaleStateComponent: Component { var base: SIMD3<Float>; var mode: Int }

        var modelURL: URL?
        var parent: ARViewContainer
        var selectedEntity: Entity?
        var plantEntities: [Entity] = []
        var initialEntityPosition: SIMD3<Float>?
        var offset: SIMD3<Float>?
        // Cache the loaded model to avoid re-downloading and speed up placements
        var cachedEntity: ModelEntity?

        init(_ parent: ARViewContainer) {
            self.parent = parent
        }

        private func rootPlantEntity(from entity: Entity) -> Entity? {
            if plantEntities.contains(entity) { return entity }
            var current: Entity? = entity
            while let parent = current?.parent {
                if plantEntities.contains(parent) { return parent }
                current = parent
            }
            return nil
        }

        private func selectEntity(_ entity: Entity) {
            // Désélectionner l'entité précédente
            if let previousEntity = selectedEntity {
                previousEntity.children.forEach {
                    if $0.name == "selectionBox" { $0.removeFromParent() }
                }
            }

            selectedEntity = entity

            if let modelEntity = entity as? ModelEntity {
                modelEntity.generateCollisionShapes(recursive: true)
                let bounds = modelEntity.visualBounds(relativeTo: nil)
                let boxSize = bounds.extents

                // Créer une boîte de sélection avec une taille minimum pour être visible
                let minSize: Float = 0.05 // 5cm minimum pour chaque dimension
                let expandedSize = SIMD3<Float>(
                    max(boxSize.x * 1.2, minSize),
                    max(boxSize.y * 1.2, minSize),
                    max(boxSize.z * 1.2, minSize)
                )

                let selectionMaterial = UnlitMaterial(color: .blue.withAlphaComponent(0.3))
                let selectionBox = ModelEntity(mesh: .generateBox(size: expandedSize), materials: [selectionMaterial])
                selectionBox.name = "selectionBox"

                entity.addChild(selectionBox)
                print("✅ Plante sélectionnée avec boîte de sélection de taille: \(expandedSize)")
            }
        }

        @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
            guard sender.state == .began,
                  let arView = sender.view as? ARView else { return }

            let location = sender.location(in: arView)

            if let entity = arView.entity(at: location) {
                if plantEntities.contains(entity) {
                    selectEntity(entity)
                    return
                } else {
                    var currentEntity: Entity? = entity
                    while let parent = currentEntity?.parent {
                        if plantEntities.contains(parent) {
                            selectEntity(parent)
                            return
                        }
                        currentEntity = parent
                    }
                }
            }

            let hits = arView.hitTest(location)
            for hit in hits {
                var currentEntity: Entity? = hit.entity
                while let entity = currentEntity {
                    if plantEntities.contains(entity) {
                        selectEntity(entity)
                        return
                    }
                    currentEntity = entity.parent
                }
            }

            print("❌ Aucune plante sélectionnée via long press")
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = sender.view as? ARView else { return }
            let location = sender.location(in: arView)

            // If tapping an existing plant, select it instead of placing a new one
            if let hit = arView.entity(at: location), let root = rootPlantEntity(from: hit) {
                selectEntity(root)
                return
            }

            // Prefer existing plane geometry first, then fall back to estimated on any alignment
            var position: SIMD3<Float>?
            if let result = arView.raycast(from: location, allowing: .existingPlaneGeometry, alignment: .any).first {
                position = SIMD3<Float>(result.worldTransform.columns.3.x,
                                        result.worldTransform.columns.3.y,
                                        result.worldTransform.columns.3.z)
            } else if let result = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first {
                position = SIMD3<Float>(result.worldTransform.columns.3.x,
                                        result.worldTransform.columns.3.y,
                                        result.worldTransform.columns.3.z)
            }

            guard let placePos = position else {
                print("ℹ️ Aucun plan détecté sous le doigt.")
                return
            }

            addPlant(at: placePos, in: arView)
        }

        @objc func handleDoubleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = sender.view as? ARView else { return }
            let location = sender.location(in: arView)

            guard let hit = arView.entity(at: location), let root = rootPlantEntity(from: hit) as? ModelEntity else { return }

            var state = root.components[ScaleStateComponent.self] ?? ScaleStateComponent(base: root.scale(relativeTo: nil), mode: 0)

            switch state.mode {
            case 0:
                root.setScale(state.base * 1.5, relativeTo: nil)
                state.mode = 1
            case 1:
                root.setScale(state.base * 0.7, relativeTo: nil)
                state.mode = 2
            default:
                root.setScale(state.base, relativeTo: nil)
                state.mode = 0
            }

            root.components.set(state)
        }

        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            guard let arView = sender.view as? ARView,
                  let selectedEntity = selectedEntity else { return }

            let location = sender.location(in: arView)

            switch sender.state {
            case .began:
                let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)
                if let result = results.first {
                    initialEntityPosition = selectedEntity.position
                    let touchPosition = SIMD3<Float>(result.worldTransform.columns.3.x,
                                                     result.worldTransform.columns.3.y,
                                                     result.worldTransform.columns.3.z)
                    offset = initialEntityPosition! - touchPosition
                }

            case .changed:
                let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)
                if let result = results.first, let _ = initialEntityPosition, let offset = offset {
                    let newPosition = SIMD3<Float>(result.worldTransform.columns.3.x,
                                                   result.worldTransform.columns.3.y,
                                                   result.worldTransform.columns.3.z) + offset
                    selectedEntity.position = newPosition
                }

            case .ended, .cancelled:
                initialEntityPosition = nil
                offset = nil

            default:
                break
            }
        }

        @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
            guard let entity = selectedEntity else { return }

            switch sender.state {
            case .began:
                // Sauvegarder l'échelle initiale au début du pinch
                print("🤏 Début du geste pinch sur l'entité")
                
            case .changed:
                let minScale: Float = 0.01  // Permettre de très petites échelles pour sortir de gros modèles
                let maxScale: Float = 5.0   // Limiter les tailles maximales
                let scaleFactor = Float(sender.scale)

                let current = entity.scale(relativeTo: nil)
                let newVal = max(minScale, min(maxScale, current.x * scaleFactor))
                let newScale = SIMD3<Float>(repeating: newVal)
                entity.setScale(newScale, relativeTo: nil)
                sender.scale = 1.0
                
                print("🔍 Nouvelle échelle appliquée: \(newScale)")
                
                // Mettre à jour le composant ScaleState si c'est un ModelEntity
                if let modelEntity = entity as? ModelEntity {
                    var state = modelEntity.components[ScaleStateComponent.self] ?? ScaleStateComponent(base: newScale, mode: 0)
                    state.base = newScale
                    modelEntity.components.set(state)
                }

            default:
                break
            }
        }

        private func autoScaledClone(from entity: ModelEntity) -> ModelEntity {
            let clone = entity.clone(recursive: true)
            
            // Utiliser directement l'échelle minimale pour éviter les plantes énormes
            let minScale: Float = 0.01  // 1% - taille minimale de dézoom
            
            print("🔍 DEBUG - Application de l'échelle minimale: \(minScale)")
            
            clone.setScale(SIMD3<Float>(repeating: minScale), relativeTo: nil)
            clone.generateCollisionShapes(recursive: true)
            return clone
        }

        func addPlant(at position: SIMD3<Float>, in arView: ARView) {
            print("📍 Tentative d'ajout de la plante à la position : \(position)")

            // If we already have a cached model, place a clone immediately
            if let cached = cachedEntity {
                let placed = autoScaledClone(from: cached)
                let anchor = AnchorEntity(world: position)
                anchor.addChild(placed)
                arView.scene.addAnchor(anchor)
                placed.components.set(ScaleStateComponent(base: placed.scale(relativeTo: nil), mode: 0))
                self.plantEntities.append(placed) // Ajouter le modèle, pas l'ancre
                print("✅ Plante placée (cache) : \(position)")
                return
            }

            // Check if model URL exists, if not, create test plant immediately
            guard let modelURL = modelURL else {
                print("❌ URL du modèle manquante - création d'un modèle de test")
                createTestPlant(at: position, in: arView)
                return
            }

            // Check for fallback URL
            if modelURL.scheme == "fallback" {
                print("🎯 URL de fallback détectée - création d'un modèle de test")
                createTestPlant(at: position, in: arView)
                return
            }

            // Try to load the model asynchronously
            Task {
                do {
                    let loaded: ModelEntity
                    
                    // Check if it's a local file URL (file scheme) or a bundle resource
                    if modelURL.isFileURL || modelURL.scheme == nil {
                        // It's a local file - load directly
                        print("📁 Chargement du fichier local : \(modelURL)")
                        loaded = try await ModelEntity(contentsOf: modelURL)
                    } else {
                        // It's a remote URL - download first
                        print("🌐 Téléchargement du modèle distant : \(modelURL)")
                        let (downloadedURL, _) = try await URLSession.shared.download(from: modelURL)
                        print("📥 Fichier téléchargé temporairement : \(downloadedURL)")
                        
                        // Create a properly named URL with .usdz extension for RealityKit to recognize
                        let documentsPath = FileManager.default.temporaryDirectory
                        let properURL = documentsPath.appendingPathComponent("downloaded_model.usdz")
                        
                        // Remove any existing file at the destination
                        try? FileManager.default.removeItem(at: properURL)
                        
                        // Move the downloaded file to a proper location with .usdz extension
                        try FileManager.default.moveItem(at: downloadedURL, to: properURL)
                        print("🔧 Fichier renommé avec extension .usdz : \(properURL)")
                        
                        loaded = try await ModelEntity(contentsOf: properURL)
                    }
                    
                    self.cachedEntity = loaded

                    await MainActor.run {
                        let placed = self.autoScaledClone(from: loaded)
                        let anchor = AnchorEntity(world: position)
                        anchor.addChild(placed)
                        arView.scene.addAnchor(anchor)
                        placed.components.set(ScaleStateComponent(base: placed.scale(relativeTo: nil), mode: 0))
                        self.plantEntities.append(placed) // Ajouter le modèle, pas l'ancre
                        print("✅ Plante ajoutée avec succès à la position : \(position)")
                    }
                } catch {
                    await MainActor.run {
                        print("❌ Erreur lors du chargement du modèle : \(error.localizedDescription)")
                        print("🔄 Création d'un modèle de test à la place")
                        // Créer un modèle de test si le fichier USDZ n'est pas trouvé
                        self.createTestPlant(at: position, in: arView)
                    }
                }
            }
        }

        private func createTestPlant(at position: SIMD3<Float>, in arView: ARView) {
            // Créer un modèle simple pour tester si l'AR fonctionne
            let trunkMesh = MeshResource.generateBox(size: [0.05, 0.2, 0.05])
            let trunkMaterial = SimpleMaterial(color: .brown, isMetallic: false)
            let trunk = ModelEntity(mesh: trunkMesh, materials: [trunkMaterial])
            trunk.position = SIMD3<Float>(0, 0.1, 0)
            
            let leavesMesh = MeshResource.generateSphere(radius: 0.08)
            let leavesMaterial = SimpleMaterial(color: .green, isMetallic: false)
            let leaves = ModelEntity(mesh: leavesMesh, materials: [leavesMaterial])
            leaves.position = SIMD3<Float>(0, 0.22, 0)
            
            let testPlant = Entity()
            testPlant.addChild(trunk)
            testPlant.addChild(leaves)
            
            let anchor = AnchorEntity(world: position)
            anchor.addChild(testPlant)
            arView.scene.addAnchor(anchor)
            self.plantEntities.append(testPlant)
            print("✅ Modèle de test (arbre simple) placé instantanément à la position : \(position)")
        }
    }
}
