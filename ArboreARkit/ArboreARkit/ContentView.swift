import SwiftUI
import ARKit
import RealityKit

// MARK: - PlantModel3D stub
// Configuration optionnelle pour personnaliser l'affichage d'un modèle 3D.
struct PlantModel3D {
    var scale: Float = 1.0
    var name: String = ""
}

// MARK: - Demo ContentView (optionnelle)
// Juste pour tester en standalone. Tu peux l'enlever si tu n'en as pas besoin.
struct ContentView: View {
    @State private var arView = ARView(frame: UIScreen.main.bounds)

    var body: some View {
        if let url = Bundle.main.url(forResource: "plant2", withExtension: "usdz") {
            ARViewContainer(
                arView: $arView,
                modelURL: url,
                modelConfig: nil   // ou un PlantModel3D de test si tu veux
            )
            .edgesIgnoringSafeArea(.all)
        } else {
            Text("Demo AR model not found (plant2.usdz)")
                .padding()
        }
    }
}

// MARK: - ARViewContainer générique (utilisé par ARViewWrapper)

struct ARViewContainer: UIViewRepresentable {
    @Binding var arView: ARView
    let modelURL: URL
    let modelConfig: PlantModel3D?

    func makeUIView(context: Context) -> ARView {
        // Config AR
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config)

        // Gestes
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )

        longPressGesture.minimumPressDuration = 0.5

        arView.addGestureRecognizer(tapGesture)
        arView.addGestureRecognizer(longPressGesture)
        arView.addGestureRecognizer(panGesture)
        arView.addGestureRecognizer(pinchGesture)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Pour l’instant rien à updater dynamiquement
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var parent: ARViewContainer
        var selectedEntity: Entity?
        var plantEntities: [Entity] = []
        var initialEntityPosition: SIMD3<Float>?
        var offset: SIMD3<Float>?

        init(_ parent: ARViewContainer) {
            self.parent = parent
        }

        // MARK: - Sélection visuelle

        private func selectEntity(_ entity: Entity) {
            // Retire l’ancienne "box" de sélection
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
                let selectionBox = ModelEntity(
                    mesh: .generateBox(size: expandedSize),
                    materials: [selectionMaterial]
                )
                selectionBox.name = "selectionBox"

                entity.addChild(selectionBox)
            }

            print("✅ Plante sélectionnée avec effet visuel")
        }

        // MARK: - Long press = sélection

        @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
            guard sender.state == .began,
                  let arView = sender.view as? ARView else { return }

            let location = sender.location(in: arView)

            // 1) entity(at:)
            if let entity = arView.entity(at: location) {
                if plantEntities.contains(entity) {
                    selectEntity(entity)
                    print("✅ Plante sélectionnée via entity(at:)")
                    return
                } else {
                    var currentEntity: Entity? = entity
                    while let parent = currentEntity?.parent {
                        if plantEntities.contains(parent) {
                            selectEntity(parent)
                            print("✅ Plante sélectionnée via parent entity")
                            return
                        }
                        currentEntity = parent
                    }
                }
            }

            // 2) hitTest
            let hits = arView.hitTest(location)
            for hit in hits {
                var currentEntity: Entity? = hit.entity
                while let entity = currentEntity {
                    if plantEntities.contains(entity) {
                        selectEntity(entity)
                        print("✅ Plante sélectionnée via hitTest")
                        return
                    }
                    currentEntity = entity.parent
                }
            }

            print("❌ Aucune plante sélectionnée via long press")
        }

        // MARK: - Tap = ajout d’une plante

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = sender.view as? ARView else { return }
            let location = sender.location(in: arView)

            let results = arView.raycast(
                from: location,
                allowing: .estimatedPlane,
                alignment: .horizontal
            )

            if let result = results.first {
                let position = SIMD3<Float>(
                    result.worldTransform.columns.3.x,
                    result.worldTransform.columns.3.y,
                    result.worldTransform.columns.3.z
                )
                addPlant(at: position, in: arView)
            }
        }

        // MARK: - Pan = déplacement

        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            guard let arView = sender.view as? ARView,
                  let selectedEntity = selectedEntity else { return }

            let location = sender.location(in: arView)

            switch sender.state {
            case .began:
                let results = arView.raycast(
                    from: location,
                    allowing: .estimatedPlane,
                    alignment: .horizontal
                )
                if let result = results.first {
                    initialEntityPosition = selectedEntity.position
                    let touchPosition = SIMD3<Float>(
                        result.worldTransform.columns.3.x,
                        result.worldTransform.columns.3.y,
                        result.worldTransform.columns.3.z
                    )
                    offset = initialEntityPosition! - touchPosition
                }

            case .changed:
                let results = arView.raycast(
                    from: location,
                    allowing: .estimatedPlane,
                    alignment: .horizontal
                )
                if let result = results.first,
                   let initialPosition = initialEntityPosition,
                   let offset = offset {
                    let newPosition = SIMD3<Float>(
                        result.worldTransform.columns.3.x,
                        result.worldTransform.columns.3.y,
                        result.worldTransform.columns.3.z
                    ) + offset

                    selectedEntity.position = newPosition
                    print("🔄 Plante déplacée à : \(newPosition)")
                }

            case .ended, .cancelled:
                initialEntityPosition = nil
                offset = nil

            default:
                break
            }
        }

        // MARK: - Pinch = scale

        @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
            guard let entity = selectedEntity else { return }

            switch sender.state {
            case .changed:
                let minScale: Float = 0.001
                let maxScale: Float = 0.05   // un peu plus large pour certains modèles
                let scaleFactor = Float(sender.scale)

                let newScale = max(
                    minScale,
                    min(maxScale, entity.scale.x * scaleFactor)
                )
                entity.setScale(SIMD3<Float>(repeating: newScale), relativeTo: nil)

                print("🔍 Nouvelle taille : \(newScale)")
                sender.scale = 1.0

            default:
                break
            }
        }

        // MARK: - Ajout de plante (utilise modelURL + modelConfig)

        func addPlant(at position: SIMD3<Float>, in arView: ARView) {
            do {
                // Chargement à partir de l’URL du bundle (local)
                let plantModel = try Entity.load(contentsOf: parent.modelURL)

                // Échelle / offset personnalisés si on a une config
                if let config = parent.modelConfig {
                    plantModel.setScale(config.scale, relativeTo: nil)
                    if config.yOffset != 0 {
                        plantModel.position.y += config.yOffset
                    }
                } else {
                    // Valeur par défaut si pas de config
                    plantModel.setScale(SIMD3<Float>(repeating: 0.002), relativeTo: nil)
                }

                plantModel.generateCollisionShapes(recursive: true)

                let anchor = AnchorEntity(world: position)
                anchor.addChild(plantModel)
                arView.scene.addAnchor(anchor)

                plantEntities.append(plantModel)

                print("✅ Plante ajoutée et détectable via le long press")
                print("📦 Modèle chargé depuis : \(parent.modelURL.lastPathComponent)")
            } catch {
                print("❌ Impossible de charger le modèle 3D depuis URL \(parent.modelURL): \(error)")
            }
        }
    }
}
