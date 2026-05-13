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
        config.environmentTexturing = ARQuality.recommended.environmentTexturing

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

    // MARK: - Teardown
    // SwiftUI calls this when the view is removed from the hierarchy.
    // Without it, the ARView + its loaded ModelEntities stayed in memory for
    // the process lifetime, causing the OOM jetsam kill observed during
    // long AR sessions.
    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
        uiView.scene.anchors.removeAll()
        coordinator.plantEntities.removeAll()
        coordinator.plantAnchors.removeAll()
        coordinator.modelTemplateByURL.removeAll()
        coordinator.selectedEntity = nil
        print("🧹 ARViewContainer dismantled — scene + caches cleared")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, ARSessionDelegate {
        var parent: ARViewContainer
        var selectedEntity: Entity?
        var plantEntities: [Entity] = []
        // Parallel array to plantEntities so we can remove the wrapping anchor
        // when we evict a plant (entity.removeFromParent alone doesn't free
        // the AnchorEntity sitting in arView.scene).
        var plantAnchors: [AnchorEntity] = []
        // Per-URL parsed template. The first placement pays the USDZ decode
        // cost; subsequent placements call `template.clone(recursive: true)`,
        // which shares the underlying MeshResource + Materials and only
        // duplicates per-instance transform state.
        var modelTemplateByURL: [URL: Entity] = [:]
        // Hard cap on concurrent placements. 20 plants × ~40 MB decoded is
        // comfortably under the iPhone 17 Pro jetsam threshold.
        private let maxConcurrentPlants = 20
        var initialEntityPosition: SIMD3<Float>?
        var offset: SIMD3<Float>?

        init(_ parent: ARViewContainer) {
            self.parent = parent
        }

        deinit {
            plantEntities.removeAll()
            plantAnchors.removeAll()
            modelTemplateByURL.removeAll()
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
                   let _ = initialEntityPosition,
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
                // 1) Parse-once template cache. The first placement pays the
                //    USDZ decode; subsequent placements clone the template,
                //    sharing MeshResource + Materials for ~free extra cost.
                let template: Entity
                if let cached = modelTemplateByURL[parent.modelURL] {
                    template = cached
                } else {
                    let loaded = try ModelEntity.load(contentsOf: parent.modelURL)
                    Self.sanitizeMaterials(loaded)
                    modelTemplateByURL[parent.modelURL] = loaded
                    template = loaded
                    print("🧩 cached template for \(parent.modelURL.lastPathComponent)")
                }

                let modelEntity = template.clone(recursive: true)

                // 2) Enforce the hard cap: evict oldest placements first.
                while plantEntities.count >= maxConcurrentPlants {
                    let oldestEntity = plantEntities.removeFirst()
                    oldestEntity.removeFromParent()
                    if !plantAnchors.isEmpty {
                        let oldestAnchor = plantAnchors.removeFirst()
                        arView.scene.removeAnchor(oldestAnchor)
                    }
                    print("♻️  Max plants reached — evicted oldest")
                }

                // 3) Scale + collision + anchor — same as before.
                let bounds = modelEntity.visualBounds(relativeTo: nil)
                let height = max(bounds.extents.y, 0.0001)
                let targetHeight: Float = 0.01
                let scale = targetHeight / height

                modelEntity.scale = SIMD3<Float>(repeating: scale)
                print("📏 Auto-scale: height=\(height) -> scale=\(scale)")

                if let me = modelEntity as? ModelEntity {
                    me.generateCollisionShapes(recursive: true)
                }

                let anchor = AnchorEntity(world: worldTransform)
                anchor.addChild(modelEntity)
                arView.scene.addAnchor(anchor)

                plantEntities.append(modelEntity)
                plantAnchors.append(anchor)

                print("✅ Plante ajoutée (\(plantEntities.count)/\(maxConcurrentPlants))")
                print("📦 Modèle : \(parent.modelURL.lastPathComponent)")
            } catch {
                print("❌ Impossible de charger le modèle 3D depuis \(parent.modelURL): \(error)")
            }
        }
    }
}
