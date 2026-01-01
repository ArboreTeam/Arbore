import SwiftUI
import ARKit
import SceneKit

struct ARMeasurementViewContainer: UIViewRepresentable {
    // Si l'erreur persiste ici, c'est qu'il reste un doublon de la classe ailleurs
    @ObservedObject var viewModel: ARMeasurementViewModel
    
    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        
        // Setup simple
        sceneView.autoenablesDefaultLighting = true
        sceneView.delegate = context.coordinator
        sceneView.session.delegate = context.coordinator
        
        // Liaison Vitale : Le ViewModel a besoin de la vue pour faire les Raycasts
        viewModel.arSession = sceneView.session
        viewModel.sceneView = sceneView
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal] // On se concentre sur le sol
        config.environmentTexturing = .automatic
        
        // Activation LiDAR si dispo pour meilleure précision
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        // Coaching Overlay (Aide l'utilisateur à trouver le sol)
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.session = sceneView.session
        coachingOverlay.activatesAutomatically = true
        sceneView.addSubview(coachingOverlay)
        
        return sceneView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        var viewModel: ARMeasurementViewModel
        
        init(viewModel: ARMeasurementViewModel) {
            self.viewModel = viewModel
        }
        
        // Appelée ~60 fois par seconde (Frame Loop)
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // C'est ici qu'on met à jour le raycast continu
            DispatchQueue.main.async {
                self.viewModel.updateLoop(cameraTransform: frame.camera.transform)
            }
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("AR Error: \(error.localizedDescription)")
        }
    }
}
