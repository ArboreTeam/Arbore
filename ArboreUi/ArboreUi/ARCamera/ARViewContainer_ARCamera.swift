// filepath: /Users/hugomichel/Documents/Arbore150/ArboreUi/ArboreUi/ARCamera/ARViewContainer_ARCamera.swift

import SwiftUI
import ARKit
import RealityKit

struct ARViewContainer: UIViewRepresentable {
    @Binding var arView: ARView
    let modelURL: URL

    func makeUIView(context: Context) -> ARView {
        // ✅ FIX: Initialiser avec la taille de l'écran pour éviter écran noir sur iPhone Pro
        arView.frame = UIScreen.main.bounds

        // ✅ Configuration pour éviter l'écran noir
        arView.cameraMode = .ar
        arView.automaticallyConfigureSession = false
        arView.renderOptions = [.disableMotionBlur]
        arView.environment.background = .cameraFeed()

        // ✅ Debug ARSession
        arView.session.delegate = context.coordinator

        // Configuration AR
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        // ⚠️ IMPORTANT: sceneDepth peut provoquer un flux caméra noir sur certains appareils/iOS (iPhone 16/17 Pro).
        // On le désactive par défaut. À réactiver plus tard via un toggle si besoin.
        // if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
        //     config.frameSemantics.insert(.sceneDepth)
        // }

        // ✅ Délai pour laisser la vue s'initialiser correctement
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            print("✅ AR Session started for ARViewContainer_ARCamera")
        }

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

        print("✅ ARViewContainer ready - model: \(modelURL.lastPathComponent)")
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Rien à mettre à jour pour l'instant
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, ARSessionDelegate {
        var parent: ARViewContainer
        var selectedEntity: Entity?
        var plantEntities: [Entity] = []
        var initialEntityPosition: SIMD3<Float>?
        var offset: SIMD3<Float>?

        init(_ parent: ARViewContainer) {
            self.parent = parent
        }

        // MARK: - ARSession debug
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("❌ ARSession didFailWithError: \(error)")
        }

        func sessionWasInterrupted(_ session: ARSession) {
            print("⚠️ ARSession was interrupted")
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            print("ℹ️ ARSession interruption ended")
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            switch camera.trackingState {
            case .normal:
                print("✅ AR tracking: normal")
            case .notAvailable:
                print("⚠️ AR tracking: notAvailable")
            case .limited(let reason):
                print("⚠️ AR tracking: limited (\(reason))")
            }
        }

        // MARK: - Sélection visuelle
        private func selectEntity(_ entity: Entity) {
            // Retirer l'ancienne box de sélection
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
                if plantEntities.contains(where: { $0 === entity }) {
                    selectEntity(entity)
                    print("✅ Plante sélectionnée via entity(at:)")
                    return
                } else {
                    var currentEntity: Entity? = entity
                    while let parent = currentEntity?.parent {
                        if plantEntities.contains(where: { $0 === parent }) {
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
                    if plantEntities.contains(where: { $0 === entity }) {
                        selectEntity(entity)
                        print("✅ Plante sélectionnée via hitTest")
                        return
                    }
                    currentEntity = entity.parent
                }
            }

            print("❌ Aucune plante sélectionnée via long press")
        }

        // MARK: - Tap = ajout de plante
        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = sender.view as? ARView else { return }
            let location = sender.location(in: arView)

            let results = arView.raycast(
                from: location,
                allowing: .estimatedPlane,
                alignment: .horizontal
            )

            print("🟦 Tap -> raycast results: \(results.count)")

            guard let result = results.first else {
                print("⚠️ Aucun plan détecté. Bouge un peu le tel et vise une surface texturée.")
                return
            }

            addPlant(with: result.worldTransform, in: arView)
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
                    if let initial = initialEntityPosition {
                        offset = initial - touchPosition
                    }
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
                let maxScale: Float = 0.2   // un peu plus large pour tester
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

        // Defensive: forces opaque blending on every PhysicallyBasedMaterial
        // in the hierarchy. Free performance-wise, prevents stray alpha values
        // in meshy-generated base color textures from triggering transparent
        // rendering in iOS ARView. Back-face culling stays default (one-sided)
        // for perf — the real geometry fix lives in the USDZ pipeline
        // (subdivisionScheme = "none" injected at packaging time).
        static func sanitizeMaterials(_ entity: Entity) {
            if var model = entity.components[ModelComponent.self] {
                model.materials = model.materials.map { material -> RealityKit.Material in
                    if var pbr = material as? PhysicallyBasedMaterial {
                        pbr.blending = .opaque
                        return pbr
                    }
                    return material
                }
                entity.components.set(model)
            }
            for child in entity.children {
                sanitizeMaterials(child)
            }
        }

        // MARK: - Ajout du modèle 3D (anchor avec transform complet)
        func addPlant(with worldTransform: simd_float4x4, in arView: ARView) {
            do {
                let modelEntity = try ModelEntity.load(contentsOf: parent.modelURL)

                // Patch meshy-generated material quirks (back-face culling +
                // alpha blending) before adding to the AR scene.
                Self.sanitizeMaterials(modelEntity)

                let bounds = modelEntity.visualBounds(relativeTo: nil)
                let height = max(bounds.extents.y, 0.0001)
                let targetHeight: Float = 0.01 // 80 cm
                let scale = targetHeight / height

                modelEntity.scale = SIMD3<Float>(repeating: scale)
                print("📏 Auto-scale: height=\(height) -> scale=\(scale)")

                modelEntity.generateCollisionShapes(recursive: true)

                // Anchor plus fiable
                let anchor = AnchorEntity(world: worldTransform)
                anchor.addChild(modelEntity)
                arView.scene.addAnchor(anchor)

                plantEntities.append(modelEntity)

                print("✅ Plante ajoutée")
                print("📦 Modèle chargé depuis : \(parent.modelURL.lastPathComponent)")
            } catch {
                print("❌ Impossible de charger le modèle 3D depuis \(parent.modelURL): \(error)")
            }
        }
    }
}
