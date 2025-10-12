import SwiftUI
import ARKit
import RealityKit

struct ARViewBasic: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var arView = ARView(frame: .zero)
    @State private var showShareSheet = false
    @State private var capturedImage: UIImage?
    @State private var isImageReady = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ARViewBasicContainer(arView: $arView)
                .edgesIgnoringSafeArea(.all)

            // Bouton Retour en haut à gauche
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding()

            // Instructions en haut au centre
            VStack {
                VStack(spacing: 8) {
                    Text("🌱 Mode AR Basique")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                    
                    Text("Pointez votre caméra vers une surface plane pour commencer")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                }
                .padding(.top, 80)
                
                Spacer()
                
                // Bouton Prendre une photo centré en bas
                Button(action: captureARView) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.title)
                        Text("Prendre une photo")
                            .fontWeight(.bold)
                    }
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .foregroundColor(.black)
                    .cornerRadius(12)
                    .shadow(radius: 5)
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: isImageReady) { _, ready in
            if ready {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showShareSheet = true
                }
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            isImageReady = false
        }) {
            if let image = capturedImage {
                ShareSheet(items: [image])
            }
        }
    }

    private func captureARView() {
        arView.snapshot(saveToHDR: false) { image in
            DispatchQueue.main.async {
                if let image = image {
                    capturedImage = image
                    isImageReady = true
                } else {
                    print("❌ Erreur lors de la capture de l'ARView")
                }
            }
        }
    }
}

struct ARViewBasicContainer: UIViewRepresentable {
    @Binding var arView: ARView

    func makeUIView(context: Context) -> ARView {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config)

        // Ajouter un plan simple pour visualiser la détection de surface
        let planeAnchor = AnchorEntity(plane: .horizontal)
        let planeMesh = MeshResource.generatePlane(width: 0.5, depth: 0.5)
        let planeMaterial = SimpleMaterial(color: .green.withAlphaComponent(0.3), isMetallic: false)
        let planeEntity = ModelEntity(mesh: planeMesh, materials: [planeMaterial])
        planeAnchor.addChild(planeEntity)
        
        arView.scene.addAnchor(planeAnchor)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
