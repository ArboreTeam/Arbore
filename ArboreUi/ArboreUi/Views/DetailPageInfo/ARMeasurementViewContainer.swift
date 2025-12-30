import SwiftUI
import ARKit
import SceneKit

struct ARMeasurementViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ARMeasurementViewModel
    
    func makeUIView(context: Context) -> ARSCNView {
        // 1. Initialisation SceneKit
        let sceneView = ARSCNView(frame: .zero)
        
        // 2. Configuration Basique
        sceneView.autoenablesDefaultLighting = true
        
        // IMPORTANT : On assigne le coordinateur aux DEUX délégués
        // 1. Pour le rendu 3D (SceneKit)
        sceneView.delegate = context.coordinator
        // 2. Pour les données brutes de la caméra (ARSession pour tes calculs)
        sceneView.session.delegate = context.coordinator
        
        // 3. Liaison avec le ViewModel
        viewModel.arSession = sceneView.session
        
        // 4. Configuration AR Standard (Sans options graphiques complexes)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        // 5. Lancement
        DispatchQueue.main.async {
            sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            viewModel.isPlacingPoints = true
        }
        
        // 6. Coaching Overlay
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
    // Il doit conformer à ARSCNViewDelegate (Vue) ET ARSessionDelegate (Données)
    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        var viewModel: ARMeasurementViewModel
        
        init(viewModel: ARMeasurementViewModel) {
            self.viewModel = viewModel
        }
        
        // --- ARSessionDelegate (Ce qui intéresse ton ViewModel) ---
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // On relaie les données de la frame au ViewModel pour le Raycasting
            DispatchQueue.main.async {
                self.viewModel.session(session, didUpdate: frame)
            }
        }
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            DispatchQueue.main.async {
                self.viewModel.session(session, didAdd: anchors)
            }
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("❌ Erreur Session AR : \(error.localizedDescription)")
        }
        
        // --- ARSCNViewDelegate (Gestion du rendu 3D) ---
        
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // CORRECTION DE L'ERREUR ICI :
            // On vérifie que le renderer est bien une ARSCNView avant d'accéder à la session
            guard let sceneView = renderer as? ARSCNView else { return }
            
            // Si tu as besoin d'accéder à la session ici pour du rendu visuel :
            if let _ = sceneView.session.currentFrame {
                // Logique de rendu optionnelle ici
            }
        }
    }
}
