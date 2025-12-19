import SwiftUI
import RealityKit
import ARKit
import Combine

struct GardenARPlacementView: View {
    let selectedPlants: [Plant]
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var selectedPlantForPlacement: Plant? = nil

    var body: some View {
        ZStack {
            // AR camera (plein écran)
            GardenARPlacementContainerView(selectedPlant: $selectedPlantForPlacement)
                .ignoresSafeArea()

            // ✅ IMPORTANT: on masque le gradient quand la sheet est ouverte
            if !showPicker {
                bottomGradient
                    .ignoresSafeArea()
            }

            // UI overlay
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
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.20))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(.white.opacity(0.10), lineWidth: 1)
                    )
            }

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            titlePill
                .padding(.top, 6)
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
        .overlay(
            Capsule().stroke(.white.opacity(0.10), lineWidth: 1)
        )
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

            Button {
                showPicker = true
            } label: {
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
                .shadow(
                    color: Color(hex: "#2BEE79").opacity(0.35),
                    radius: 18,
                    x: 0,
                    y: 10
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }
}

//
// MARK: - AR View (copié/collé du code qui marche, noms changés)
//

fileprivate struct GardenARPlacementContainerView: UIViewRepresentable {
    @Binding var selectedPlant: Plant?

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configuration AR (comme ton fichier qui marche)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        arView.automaticallyConfigureSession = true
        arView.session.run(config)

        // Gestes (on ne garde QUE tap pour le placement, le reste tu pourras rajouter plus tard)
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(GardenCoordinator.handleTapPlace(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        // Reticle
        context.coordinator.arView = arView
        context.coordinator.addPlacementReticle()
        context.coordinator.currentPlant = selectedPlant

        print("✅ GardenARPlacementContainerView ready")
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.currentPlant = selectedPlant
    }

    func makeCoordinator() -> GardenCoordinator {
        GardenCoordinator(self)
    }

    // MARK: - Coordinator (copié/collé style ARViewContainer, noms changés)
    final class GardenCoordinator: NSObject {
        var parent: GardenARPlacementContainerView
        weak var arView: ARView?

        var currentPlant: Plant?
        var placedEntities: [Entity] = []

        private var reticleEntity: Entity?
        private var subscriptions = Set<AnyCancellable>()

        init(_ parent: GardenARPlacementContainerView) {
            self.parent = parent
        }

        // MARK: - Reticle (comme ton ancien code)
        func addPlacementReticle() {
            guard let arView else { return }

            let mesh = MeshResource.generateSphere(radius: 0.008)
            let mat = SimpleMaterial(
                color: UIColor(Color(hex: "#2BEE79")),
                isMetallic: false
            )
            let dot = ModelEntity(mesh: mesh, materials: [mat])
            dot.name = "reticle_dot"

            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(dot)
            arView.scene.addAnchor(anchor)
            reticleEntity = dot

            arView.scene
                .subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                    self?.updatePlacementReticle()
                }
                .store(in: &subscriptions)
        }

        private func updatePlacementReticle() {
            guard let arView, let reticleEntity else { return }

            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)

            if let result = arView
                .raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal)
                .first
            {
                let t = result.worldTransform
                reticleEntity.position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                reticleEntity.isEnabled = true
            } else {
                reticleEntity.isEnabled = false
            }
        }

        // MARK: - Tap = ajout de plante (copié/collé de ton code qui marche, noms changés)
        @objc func handleTapPlace(_ sender: UITapGestureRecognizer) {
            guard let arView = sender.view as? ARView else { return }
            let location = sender.location(in: arView)

            let results = arView.raycast(
                from: location,
                allowing: .estimatedPlane,
                alignment: .horizontal
            )

            print("🟦 Tap(place) -> raycast results: \(results.count)")

            guard let result = results.first else {
                print("⚠️ Aucun plan détecté. Bouge un peu le tel et vise une surface texturée.")
                return
            }

            // modèle choisi
            guard let plant = currentPlant, let modelURL = plant.localModelURL else {
                print("⚠️ Aucune plante sélectionnée (ou pas de modèle). Fallback cylindre.")
                addFallbackCylinder(at: result.worldTransform, in: arView)
                return
            }

            addPlantAtTransform(worldTransform: result.worldTransform, in: arView, modelURL: modelURL, plantName: plant.name)
        }

        // MARK: - Ajout du modèle 3D (copié/collé de ton addPlant, SANS factoriser)
        func addPlantAtTransform(worldTransform: simd_float4x4, in arView: ARView, modelURL: URL, plantName: String) {
            do {
                let modelEntity = try ModelEntity.load(contentsOf: modelURL)

                let bounds = modelEntity.visualBounds(relativeTo: nil)
                let height = max(bounds.extents.y, 0.0001)

                // ⚠️ C'EST LE MÊME QUE TON FICHIER (0.01) => garde-le si c’est ce qui marche chez toi
                let targetHeight: Float = 0.01
                let scale = targetHeight / height

                modelEntity.scale = SIMD3<Float>(repeating: scale)
                print("📏 Auto-scale: height=\(height) -> scale=\(scale) | plant=\(plantName)")

                modelEntity.generateCollisionShapes(recursive: true)

                let anchor = AnchorEntity(world: worldTransform)
                anchor.addChild(modelEntity)
                arView.scene.addAnchor(anchor)

                placedEntities.append(modelEntity)

                print("✅ Plante ajoutée")
                print("📦 Modèle chargé depuis : \(modelURL.lastPathComponent)")
            } catch {
                print("❌ Impossible de charger le modèle 3D depuis \(modelURL): \(error)")
            }
        }

        // MARK: - Fallback cylindre (si pas de modèle)
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
    }
}
