import SwiftUI
import ARKit
import RealityKit

struct ContentView: View {
    var body: some View {
        ARViewContainer().edgesIgnoringSafeArea(.all)
    }
}

struct ARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

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
                    print("🔄 Plante déplacée à : \(newPosition)")
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

                print("🔍 Nouvelle taille : \(newScale)")
                sender.scale = 1.0

            default:
                break
            }
        }


        func addPlant(at position: SIMD3<Float>, in arView: ARView) {
            guard let plantModel = try? Entity.load(named: "plant.usdz") else {
                print("❌ Impossible de charger plant.usdz")
                return
            }

            plantModel.setScale(SIMD3<Float>(0.002, 0.002, 0.002), relativeTo: nil)

            plantModel.generateCollisionShapes(recursive: true)

            let anchor = AnchorEntity(world: position)
            anchor.addChild(plantModel)
            arView.scene.addAnchor(anchor)

            plantEntities.append(plantModel)

            print("✅ Plante ajoutée et détectable via le long press")
        }
    }
}
