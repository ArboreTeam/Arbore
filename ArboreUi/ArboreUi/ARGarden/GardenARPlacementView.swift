import SwiftUI
import RealityKit
import ARKit
import Combine

struct GardenARPlacementView: View {
    let selectedPlants: [Plant]
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false

    var body: some View {
        ZStack {
            // AR camera (plein écran)
            GardenARContainerView()
                .ignoresSafeArea()

            // UI overlay
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
        }
        .sheet(isPresented: $showPicker) {
            // Placeholder temporaire
            VStack(spacing: 16) {
                Text("Ajout de plantes (bientôt)")
                    .font(.headline)
                Text("On branchera le catalogue ici ensuite.")
                    .foregroundColor(.secondary)
                Button("Fermer") { showPicker = false }
                    .padding(.top, 8)
            }
            .padding()
            .presentationDetents([.medium])
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

            // Espace symétrique à droite
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

    // MARK: - Bottom bar

    private var bottomBar: some View {
        ZStack {
            // 🔥 Gradient large et stable
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
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 18) {
                Text("Touchez une surface pour placer une plante")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.90))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 2)

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

                        Text("Ajouter une plante")
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
}

//
// MARK: - AR View
//

fileprivate struct GardenARContainerView: UIViewRepresentable {

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Config AR simple
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic

        arView.session.run(
            config,
            options: [.removeExistingAnchors, .resetTracking]
        )

        // Tap gesture
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tap)

        context.coordinator.arView = arView
        context.coordinator.addReticle()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        weak var arView: ARView?
        private var reticleEntity: Entity?
        private var subscriptions = Set<AnyCancellable>()

        func addReticle() {
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
                    self?.updateReticle()
                }
                .store(in: &subscriptions)
        }

        private func updateReticle() {
            guard let arView, let reticleEntity else { return }

            let center = CGPoint(
                x: arView.bounds.midX,
                y: arView.bounds.midY
            )

            if let result = arView
                .raycast(
                    from: center,
                    allowing: .estimatedPlane,
                    alignment: .horizontal
                )
                .first {

                let t = result.worldTransform
                reticleEntity.position = SIMD3<Float>(
                    t.columns.3.x,
                    t.columns.3.y,
                    t.columns.3.z
                )
                reticleEntity.isEnabled = true
            } else {
                reticleEntity.isEnabled = false
            }
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView else { return }

            let location = sender.location(in: arView)

            if let result = arView
                .raycast(
                    from: location,
                    allowing: .estimatedPlane,
                    alignment: .horizontal
                )
                .first {

                let mesh = MeshResource.generateCylinder(
                    height: 0.18,
                    radius: 0.06
                )
                let mat = SimpleMaterial(
                    color: UIColor(Color(hex: "#2BEE79"))
                        .withAlphaComponent(0.95),
                    isMetallic: false
                )

                let entity = ModelEntity(
                    mesh: mesh,
                    materials: [mat]
                )
                entity.name = "test_plant"
                entity.position.y = 0.09

                let anchor = AnchorEntity(
                    world: result.worldTransform
                )
                anchor.addChild(entity)
                arView.scene.addAnchor(anchor)

                UIImpactFeedbackGenerator(
                    style: .light
                ).impactOccurred()
            }
        }
    }
}
