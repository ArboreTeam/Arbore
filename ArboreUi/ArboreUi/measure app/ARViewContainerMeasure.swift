// filepath: /Users/hugomichel/Documents/Arbore150/ArboreUi/ArboreUi/measure app/ARViewContainerMeasure.swift
//
//  ARViewContainerMeasure.swift
//  measure app
//
//  Created by hugo rath on 05/12/2025.
//

import SwiftUI
import RealityKit
import ARKit
import Combine

// MARK: - Saved Plan Structure
struct SavedPlan: Identifiable, Codable {
    let id: UUID
    let points: [SIMD3<Float>]
    let timestamp: Date
    var name: String
}

final class ARMeasureModel: ObservableObject {
    @Published var points3D: [SIMD3<Float>] = []
    @Published var isFinished: Bool = false
    @Published var previewPoint: SIMD3<Float>? = nil
    
    // Plan view transformations
    @Published var planScale: CGFloat = 1.0
    @Published var planRotation: Double = 0.0
    @Published var planOffset: CGSize = .zero
    
    // Saved plans
    @Published var savedPlans: [SavedPlan] = []
    @Published var showSavedPlans: Bool = false
    
    func addPoint(_ p: SIMD3<Float>) {
        guard !isFinished else { return }
        points3D.append(p)
    }
    
    func updatePreviewPoint(_ p: SIMD3<Float>?) {
        previewPoint = p
    }
    
    func clearPoints() {
        points3D.removeAll()
        isFinished = false
        previewPoint = nil
        resetPlanView()
    }
    
    func toggleFinish() {
        isFinished.toggle()
        previewPoint = nil
    }
    
    func resetPlanView() {
        planScale = 1.0
        planRotation = 0.0
        planOffset = .zero
    }
    
    func savePlan() {
        guard !points3D.isEmpty else { return }
        let plan = SavedPlan(
            id: UUID(),
            points: points3D,
            timestamp: Date(),
            name: "Plan - \(Date().formatted(date: .abbreviated, time: .shortened))"
        )
        savedPlans.insert(plan, at: 0)
        PersistenceManager.savePlans(savedPlans)
    }
    
    func loadSavedPlans() {
        savedPlans = PersistenceManager.loadPlans()
    }
    
    func deletePlan(_ plan: SavedPlan) {
        savedPlans.removeAll { $0.id == plan.id }
        PersistenceManager.savePlans(savedPlans)
    }
}

// MARK: - Persistence Manager
class PersistenceManager {
    static let plansKey = "savedPlans"
    
    static func savePlans(_ plans: [SavedPlan]) {
        if let encoded = try? JSONEncoder().encode(plans) {
            UserDefaults.standard.set(encoded, forKey: plansKey)
        }
    }
    
    static func loadPlans() -> [SavedPlan] {
        if let data = UserDefaults.standard.data(forKey: plansKey),
           let decoded = try? JSONDecoder().decode([SavedPlan].self, from: data) {
            return decoded
        }
        return []
    }
}

struct ARViewContainerMesure: UIViewRepresentable {
    @ObservedObject var model: ARMeasureModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        
        let config: ARWorldTrackingConfiguration
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config = ARWorldTrackingConfiguration()
            config.sceneReconstruction = .mesh
        } else {
            config = ARWorldTrackingConfiguration()
        }
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        arView.session.run(config)
        arView.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:))))
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        arView.addGestureRecognizer(panGesture)
        
        context.coordinator.arView = arView
        context.coordinator.model = model
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // nothing for now
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        weak var arView: ARView?
        var model: ARMeasureModel?
        
        // MARK: - Tap Gesture (placer un point)
        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = arView, let model = model else { return }
            let location = sender.location(in: arView)
            
            if let position = findBestHitPosition(arView, at: location) {
                placeAnchorVisual(at: position)
                model.addPoint(position)
                model.updatePreviewPoint(position)
            }
        }
        
        // MARK: - Pan Gesture (tracker la ligne en temps réel)
        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            guard let arView = arView, let model = model, !model.points3D.isEmpty else { return }
            
            let location = sender.location(in: arView)
            
            switch sender.state {
            case .began, .changed:
                if let position = findBestHitPosition(arView, at: location) {
                    model.updatePreviewPoint(position)
                }
            case .ended, .cancelled:
                model.updatePreviewPoint(nil)
            @unknown default:
                break
            }
        }
        
        // MARK: - Hit Detection
        private func findBestHitPosition(_ arView: ARView, at location: CGPoint) -> SIMD3<Float>? {
            if let query = arView.makeRaycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .any) {
                let results = arView.session.raycast(query)
                if let result = results.first {
                    return extractPosition(from: result.worldTransform)
                }
            }
            
            if let query = arView.makeRaycastQuery(from: location, allowing: .existingPlaneInfinite, alignment: .any) {
                let results = arView.session.raycast(query)
                if let result = results.first {
                    return extractPosition(from: result.worldTransform)
                }
            }
            
            let existingPlaneHits = arView.hitTest(location, types: [.existingPlaneUsingExtent, .existingPlane])
            if let hit = existingPlaneHits.first {
                return extractPosition(from: hit.worldTransform)
            }
            
            if let query = arView.makeRaycastQuery(from: location, allowing: .estimatedPlane, alignment: .any) {
                let results = arView.session.raycast(query)
                if let result = results.first {
                    return extractPosition(from: result.worldTransform)
                }
            }
            
            let featureHits = arView.hitTest(location, types: [.featurePoint])
            if let hit = featureHits.first {
                return extractPosition(from: hit.worldTransform)
            }
            
            return calculatePositionFromCamera(arView, tapLocation: location)
        }
        
        private func extractPosition(from transform: simd_float4x4) -> SIMD3<Float> {
            return SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        }
        
        private func calculatePositionFromCamera(_ arView: ARView, tapLocation: CGPoint) -> SIMD3<Float>? {
            guard let frame = arView.session.currentFrame else { return nil }
            
            let camera = frame.camera
            let viewport = arView.bounds
            let intrinsics = camera.intrinsics
            
            let imagePoint = SIMD2<Float>(Float(tapLocation.x), Float(tapLocation.y))
            
            let rayX = (imagePoint.x - intrinsics.columns.2.x) / intrinsics.columns.0.x
            let rayY = (imagePoint.y - intrinsics.columns.2.y) / intrinsics.columns.1.y
            let rayZ = Float(1.0)
            
            let rayInCameraSpace = normalize(SIMD3<Float>(rayX, rayY, rayZ))
            
            let cameraTransform = camera.transform
            let col0 = SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z)
            let col1 = SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z)
            let col2 = SIMD3<Float>(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
            
            let rayInWorldSpace = col0 * rayInCameraSpace.x +
                                 col1 * rayInCameraSpace.y +
                                 col2 * rayInCameraSpace.z
            
            let cameraPosition = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
            
            let distance: Float = 1.0
            let position = cameraPosition + normalize(rayInWorldSpace) * distance
            
            return position
        }
        
        func placeAnchorVisual(at position: SIMD3<Float>) {
            guard let arView = arView else { return }
            let sphere = MeshResource.generateSphere(radius: 0.02)
            let mat = SimpleMaterial(color: .yellow, isMetallic: false)
            let ent = ModelEntity(mesh: sphere, materials: [mat])
            ent.position = position
            let anchor = AnchorEntity(world: position)
            anchor.addChild(ent)
            arView.scene.addAnchor(anchor)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
                anchor.removeFromParent()
            }
        }
    }
}
