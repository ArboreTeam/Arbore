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

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))

        longPressGesture.minimumPressDuration = 0.5

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
        var modelURL: URL?
        var parent: ARViewContainer
        var selectedEntity: Entity?
        var plantEntities: [Entity] = []
        var initialEntityPosition: SIMD3<Float>?
        var offset: SIMD3<Float>?

        init(_ parent: ARViewContainer) {
            self.parent = parent
        }

        private func selectEntity(_ entity: Entity) {
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

                let expandedSize = SIMD3<Float>(
                    boxSize.x * 1.2,
                    boxSize.y * 1.2,
                    boxSize.z * 1.2
                )

                let selectionMaterial = UnlitMaterial(color: .blue.withAlphaComponent(0.3))
                let selectionBox = ModelEntity(mesh: .generateBox(size: expandedSize), materials: [selectionMaterial])
                selectionBox.name = "selectionBox"

                entity.addChild(selectionBox)
            }

            print("✅ Plante sélectionnée avec effet visuel")
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

            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)
            if let result = results.first {
                let position = SIMD3<Float>(result.worldTransform.columns.3.x,
                                            result.worldTransform.columns.3.y,
                                            result.worldTransform.columns.3.z)
                addPlant(at: position, in: arView)
            }
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
                if let result = results.first, let initialPosition = initialEntityPosition, let offset = offset {
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
            case .changed:
                let minScale: Float = 0.001
                let maxScale: Float = 0.01
                let scaleFactor = Float(sender.scale)

                let newScale = max(minScale, min(maxScale, entity.scale.x * scaleFactor))
                entity.setScale(SIMD3<Float>(repeating: newScale), relativeTo: nil)
                sender.scale = 1.0

            default:
                break
            }
        }

        func addPlant(at position: SIMD3<Float>, in arView: ARView) {
            guard let modelURL = modelURL else {
                print("❌ URL du modèle manquante")
                return
            }

            print("📍 Tentative d'ajout de la plante à la position : \(position)")
            print("🌐 URL du modèle distant : \(modelURL)")

            Task {
                do {
                    let (downloadedURL, _) = try await URLSession.shared.download(from: modelURL)
                    print("📥 Fichier téléchargé temporairement : \(downloadedURL)")

                    let destinationURL = downloadedURL
                        .deletingLastPathComponent()
                        .appendingPathComponent("model.usdz")

                    try? FileManager.default.removeItem(at: destinationURL)
                    try FileManager.default.moveItem(at: downloadedURL, to: destinationURL)
                    print("📦 Fichier déplacé à : \(destinationURL)")

                    let request = Entity.loadAsync(contentsOf: destinationURL)
                    let entity = try await request

                    print("🔍 Type d'entité chargée : \(type(of: entity))")

                    if let modelEntity = entity as? ModelEntity {
                        print("✅ C'est bien un ModelEntity ✅")
                        modelEntity.setScale(SIMD3<Float>(0.05, 0.05, 0.05), relativeTo: nil)
                        modelEntity.generateCollisionShapes(recursive: true)

                        let anchor = AnchorEntity(world: SIMD3(position.x, position.y + 0.01, position.z))
                        anchor.addChild(modelEntity)
                        arView.scene.addAnchor(anchor)

                        plantEntities.append(modelEntity)
                        print("🪴 Modèle 3D ajouté avec succès.")
                    } else if let refEntity = entity as? HasAnchoring {
                        print("⚠️ L'entité est de type HasAnchoring mais pas un ModelEntity.")
                        print("🧪 Essaie de le convertir ou vérifie ton .usdz avec Reality Composer Pro.")
                    } else {
                        print("❌ L'entité chargée n'est pas supportée : \(type(of: entity))")
                        return
                    }
                } catch {
                    print("❌ Erreur lors du chargement de l'entité : \(error.localizedDescription)")
                }
            }
        }
    }
}
