import SwiftUI
import RealityKit
import ARKit
import Combine
import Foundation
import simd

struct GardenARPlacementView: View {
    let selectedPlants: [Plant]
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var selectedPlantForPlacement: Plant? = nil

    var body: some View {
        ZStack {
            GardenARPlacementContainerView(selectedPlant: $selectedPlantForPlacement)
                .ignoresSafeArea()

            if !showPicker {
                bottomGradient
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
            }
            .safeAreaInset(edge: .bottom) {
                bottomContent
            }
        }
        .sheet(isPresented: $showPicker) {
            PlantCatalogARView { plant in
                selectedPlantForPlacement = plant
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(.clear)
        }
        .onAppear {
            if selectedPlantForPlacement == nil {
                selectedPlantForPlacement = selectedPlants.first
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.20))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))
            }

            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            titlePill.padding(.top, 6)
        }
    }

    private var titlePill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: "#2BEE79"))
                .frame(width: 8, height: 8)
                .shadow(color: Color(hex: "#2BEE79").opacity(0.8), radius: 8)

            Text("PLACEMENT AR")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .tracking(1.1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.20))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
    }

    // MARK: - Bottom gradient

    private var bottomGradient: some View {
        VStack {
            Spacer()
            LinearGradient(
                colors: [
                    .black.opacity(0.0),
                    .black.opacity(0.40),
                    .black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 320)
        }
    }

    // MARK: - Bottom content

    private var bottomContent: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("Touchez une surface pour placer une plante")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.90))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 2)

                if let p = selectedPlantForPlacement {
                    Text("Plante active : \(p.name)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.80))
                } else {
                    Text("Aucune plante sélectionnée")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.80))
                }
            }

            // ✅ Save / Load
            HStack(spacing: 12) {
                Button {
                    NotificationCenter.default.post(name: .gardenARSave, object: nil)
                } label: {
                    Text("Save")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                }

                Button {
                    NotificationCenter.default.post(name: .gardenARLoad, object: nil)
                } label: {
                    Text("Load")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                }
            }
            .padding(.top, 2)

            Button { showPicker = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "#102217"))
                    }

                    Text("Choisir une plante")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "#102217"))
                }
                .padding(.horizontal, 18)
                .frame(height: 64)
                .background(Color(hex: "#2BEE79"))
                .clipShape(Capsule())
                .shadow(color: Color(hex: "#2BEE79").opacity(0.35), radius: 18, x: 0, y: 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }
}

//
// MARK: - AR View
//

fileprivate struct GardenARPlacementContainerView: UIViewRepresentable {
    @Binding var selectedPlant: Plant?

    func makeUIView(context: Context) -> ARView {
        // ✅ FIX CAMetalLayer: Initialiser avec la taille de l'écran pour éviter allocation failed
        let arView = ARView(frame: UIScreen.main.bounds)

        // ✅ Configuration pour éviter l'écran noir et erreurs Metal
        arView.cameraMode = .ar
        arView.automaticallyConfigureSession = false
        arView.session.delegate = context.coordinator
        arView.renderOptions = [.disableMotionBlur]

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        // ⚠️ IMPORTANT: sceneDepth peut provoquer un flux caméra noir sur certains appareils/iOS.
        // On le désactive par défaut. À réactiver plus tard via un toggle si besoin.
        // if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
        //     config.frameSemantics.insert(.sceneDepth)
        // }

        // ✅ Délai pour laisser la vue s'initialiser correctement avant de lancer la session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }

        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(GardenCoordinator.handleTapPlace(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        context.coordinator.arView = arView
        context.coordinator.addPlacementReticle()
        context.coordinator.startReticleUpdates()
        context.coordinator.currentPlant = selectedPlant

        // ✅ Notifications Save/Load
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(GardenCoordinator.handleSaveNotif),
            name: .gardenARSave,
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(GardenCoordinator.handleLoadNotif),
            name: .gardenARLoad,
            object: nil
        )

        print("✅ GardenARPlacementContainerView ready")
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.currentPlant = selectedPlant
    }

    func makeCoordinator() -> GardenCoordinator {
        GardenCoordinator(self)
    }

    final class GardenCoordinator: NSObject, ARSessionDelegate {
        var parent: GardenARPlacementContainerView
        weak var arView: ARView?

        var currentPlant: Plant?

        // ✅ persisté: ce qu’on va écrire dans un fichier JSON
        private var placedPlants: [PersistedPlant] = []

        private var reticleAnchor: AnchorEntity?
        private var subscriptions = Set<AnyCancellable>()

        // ✅ On stocke le dernier transform du reticle (celui du centre d’écran)
        private var lastReticleWorldTransform: simd_float4x4?

        // ✅ offset constant (évite z-fighting)
        private let reticleYOffset: Float = 0.002

        init(_ parent: GardenARPlacementContainerView) {
            self.parent = parent
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        // ✅ Debug ARSession
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("❌ [GardenAR] ARSession didFailWithError: \(error)")
        }

        func sessionWasInterrupted(_ session: ARSession) {
            print("⚠️ [GardenAR] ARSession was interrupted")
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            print("ℹ️ [GardenAR] ARSession interruption ended")
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            switch camera.trackingState {
            case .normal:
                // print("✅ [GardenAR] tracking normal")
                break
            case .notAvailable:
                print("⚠️ [GardenAR] tracking not available")
            case .limited(let reason):
                print("⚠️ [GardenAR] tracking limited: \(reason)")
            }
        }

        // MARK: - Reticle
        func addPlacementReticle() {
            guard let arView else { return }

            let anchor = AnchorEntity(world: .zero)
            anchor.name = "reticle_anchor"

            if let texturedPlane = makeTexturedReticlePlane() {
                anchor.addChild(texturedPlane)
            } else {
                anchor.addChild(makeFallbackReticlePlane())
            }

            arView.scene.addAnchor(anchor)
            reticleAnchor = anchor
        }

        private func makeTexturedReticlePlane() -> ModelEntity? {
            let texture: TextureResource
            do {
                texture = try TextureResource.load(named: "placement_ring")
            } catch {
                print("❌ Texture 'placement_ring' introuvable: \(error)")
                return nil
            }

            var mat = UnlitMaterial()
            mat.baseColor = .texture(texture)
            mat.tintColor = UIColor.white.withAlphaComponent(0.95)

            let plane = ModelEntity(
                mesh: .generatePlane(width: 0.22, depth: 0.22),
                materials: [mat]
            )
            plane.name = "reticle_plane"

            return plane
        }

        private func makeFallbackReticlePlane() -> ModelEntity {
            var mat = UnlitMaterial()
            mat.color = .init(tint: UIColor.white.withAlphaComponent(0.7), texture: nil)

            let plane = ModelEntity(
                mesh: .generatePlane(width: 0.22, depth: 0.22),
                materials: [mat]
            )
            plane.name = "reticle_plane"
            return plane
        }

        func startReticleUpdates() {
            guard let arView else { return }

            arView.scene
                .subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                    self?.updatePlacementReticle()
                }
                .store(in: &subscriptions)
        }

        private func updatePlacementReticle() {
            guard let arView, let reticleAnchor else { return }

            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)

            if let result = arView
                .raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal)
                .first
            {
                // ✅ On garde le transform ORIGINAL (sans offset) pour poser la plante
                lastReticleWorldTransform = result.worldTransform

                // ✅ On applique l’offset AU RING sans l’accumuler
                var t = result.worldTransform
                t.columns.3.y += reticleYOffset
                reticleAnchor.transform.matrix = t

                reticleAnchor.isEnabled = true

                if let plane = reticleAnchor.findEntity(named: "reticle_plane") {
                    let time = Float(CACurrentMediaTime())
                    let pulse = 1.0 + 0.05 * sin(time * 3.0)
                    plane.scale = SIMD3<Float>(repeating: pulse)
                }
            } else {
                reticleAnchor.isEnabled = false
                lastReticleWorldTransform = nil
            }
        }

        // MARK: - Tap = ajout de plante
        @objc func handleTapPlace(_ sender: UITapGestureRecognizer) {
            guard let arView = sender.view as? ARView else { return }

            // ✅ On place SUR LE RETICLE (centre), donc jamais de décalage
            guard let worldTransform = lastReticleWorldTransform else {
                print("⚠️ Reticle pas dispo (pas de plan). Bouge un peu le tel.")
                return
            }

            guard let plant = currentPlant else {
                print("⚠️ Aucune plante sélectionnée.")
                return
            }

            guard let modelURL = plant.localModelURL else {
                print("⚠️ Pas de modèle pour \(plant.name). Fallback cylindre.")
                addFallbackCylinder(at: worldTransform, in: arView)
                return
            }

            addPlantAtTransform(
                worldTransform: worldTransform,
                in: arView,
                modelURL: modelURL,
                plant: plant
            )
        }

        // MARK: - Ajout du modèle 3D
        func addPlantAtTransform(worldTransform: simd_float4x4, in arView: ARView, modelURL: URL, plant: Plant) {
            do {
                let modelEntity = try ModelEntity.load(contentsOf: modelURL)

                let bounds = modelEntity.visualBounds(relativeTo: nil)
                let height = max(bounds.extents.y, 0.0001)

                let targetHeight: Float = 0.01
                let scale = targetHeight / height

                modelEntity.scale = SIMD3<Float>(repeating: scale)
                print("📏 Auto-scale: height=\(height) -> scale=\(scale) | plant=\(plant.name)")

                modelEntity.generateCollisionShapes(recursive: true)

                let anchor = AnchorEntity(world: worldTransform)
                anchor.name = "plant_anchor_\(plant.id)"
                anchor.addChild(modelEntity)
                arView.scene.addAnchor(anchor)

                // ✅ Persist data
                let persisted = PersistedPlant(
                    plantID: plant.id,
                    plantName: plant.name,
                    modelURLString: plant.modelURL ?? "",
                    transform: matrixToFloatArray(worldTransform)
                )
                placedPlants.append(persisted)

                print("✅ Plante ajoutée: \(plant.name) (\(plant.id))")
                print("📦 Modèle chargé depuis : \(modelURL.lastPathComponent)")
            } catch {
                print("❌ Impossible de charger le modèle 3D depuis \(modelURL): \(error)")
            }
        }

        // MARK: - Fallback cylindre
        func addFallbackCylinder(at worldTransform: simd_float4x4, in arView: ARView) {
            let mesh = MeshResource.generateCylinder(height: 0.18, radius: 0.06)
            let mat = SimpleMaterial(
                color: UIColor(Color(hex: "#2BEE79")).withAlphaComponent(0.95),
                isMetallic: false
            )
            let entity = ModelEntity(mesh: mesh, materials: [mat])
            entity.name = "test_plant"
            entity.position.y = 0.09

            let anchor = AnchorEntity(world: worldTransform)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        // MARK: - Save / Load notifications
        @objc func handleSaveNotif() { saveCurrentExperience() }
        @objc func handleLoadNotif() { loadSavedExperience() }

        // MARK: - Save / Load (ARWorldMap + plants)
        func saveCurrentExperience() {
            guard let arView else { return }

            arView.session.getCurrentWorldMap { [weak self] worldMap, error in
                guard let self else { return }

                if let error {
                    print("❌ getCurrentWorldMap error: \(error)")
                    return
                }
                guard let worldMap else {
                    print("❌ No worldMap available")
                    return
                }

                do {
                    let mapData = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
                    try mapData.write(to: worldMapFileURL, options: [.atomic])

                    let scene = PersistedARScene(savedAt: Date(), plants: self.placedPlants)
                    let sceneData = try JSONEncoder().encode(scene)
                    try sceneData.write(to: sceneFileURL, options: [.atomic])

                    print("✅ Saved worldMap -> \(worldMapFileURL.lastPathComponent)")
                    print("✅ Saved scene -> \(sceneFileURL.lastPathComponent) plants=\(self.placedPlants.count)")

                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } catch {
                    print("❌ Save failed: \(error)")
                }
            }
        }

        func loadSavedExperience() {
            guard let arView else { return }

            do {
                let mapData = try Data(contentsOf: worldMapFileURL)
                guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData) else {
                    print("❌ Could not unarchive ARWorldMap")
                    return
                }

                let sceneData = try Data(contentsOf: sceneFileURL)
                let scene = try JSONDecoder().decode(PersistedARScene.self, from: sceneData)

                let config = ARWorldTrackingConfiguration()
                config.planeDetection = [.horizontal, .vertical]
                config.environmentTexturing = .automatic
                config.initialWorldMap = worldMap

                // reset
                arView.scene.anchors.removeAll()
                self.placedPlants.removeAll()

                // reticle back
                addPlacementReticle()
                startReticleUpdates()

                arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

                // Re-place plants (bundle lookup)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    var restoredCount = 0

                    for p in scene.plants {
                        guard let t = floatArrayToMatrix(p.transform) else { continue }

                        // On retrouve l’URL du modèle dans le Bundle, comme ton Plant.localModelURL
                        guard let modelURL = resourceURLFromModelURLString(p.modelURLString) else {
                            print("❌ Restore: modèle introuvable pour \(p.plantName) modelURL=\(p.modelURLString)")
                            continue
                        }

                        // On reconstruit un Plant minimal (juste pour réutiliser addPlantAtTransform)
                        // (Si tu préfères, je peux faire une variante addPlantAtTransform(..., plantID/name/urlString))
                        let pseudoPlant = Plant.stubForRestore(
                            id: p.plantID,
                            name: p.plantName,
                            type: "",
                            modelURL: p.modelURLString
                        )

                        self.addPlantAtTransform(worldTransform: t, in: arView, modelURL: modelURL, plant: pseudoPlant)
                        restoredCount += 1
                    }

                    print("✅ Loaded scene: restored=\(restoredCount)/\(scene.plants.count) savedAt=\(scene.savedAt)")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } catch {
                print("❌ Load failed: \(error)")
            }
        }
    }
}
