import SwiftUI
import ARKit
import RealityKit
import Combine

// MARK: - AR Measurement ViewModel

class ARMeasurementViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    
    @Published var isPlacingPoints = false
    @Published var canPlacePoint = false
    @Published var canReset = false
    @Published var isComplete = false
    
    @Published var diameter: Float?
    @Published var height: Float?
    @Published var currentStep: MeasurementStep = .scanSurface
    
    @Published var currentMeasurement: PotMeasurement?
    
    // Manual input
    @Published var manualDiameter: String = ""
    @Published var manualHeight: String = ""
    @Published var selectedShape: PotShape = .round
    @Published var selectedMaterial: PotMaterial? = nil
    @Published var hasDrainage: Bool = true
    @Published var notes: String = ""
    
    // MARK: - Internal Properties
    
    var arSession: ARSession?
    
    // MARK: - Private Properties
    
    private var measurementPoints: [SIMD3<Float>] = []
    private var currentPlaneAnchor: ARPlaneAnchor?
    
    // MARK: - Computed Properties
    
    var currentInstruction: MeasurementInstruction {
        switch currentStep {
        case .scanSurface:
            return MeasurementInstruction(
                title: NSLocalizedString("MEASURE_STEP_SCAN_TITLE", comment: ""),
                description: NSLocalizedString("MEASURE_STEP_SCAN_DESC", comment: ""),
                icon: "camera.metering.center.weighted"
            )
        case .measureDiameter:
            return MeasurementInstruction(
                title: NSLocalizedString("MEASURE_STEP_DIAMETER_TITLE", comment: ""),
                description: NSLocalizedString("MEASURE_STEP_DIAMETER_DESC", comment: ""),
                icon: "arrow.left.and.right"
            )
        case .measureHeight:
            return MeasurementInstruction(
                title: NSLocalizedString("MEASURE_STEP_HEIGHT_TITLE", comment: ""),
                description: NSLocalizedString("MEASURE_STEP_HEIGHT_DESC", comment: ""),
                icon: "arrow.up.and.down"
            )
        case .complete:
            return MeasurementInstruction(
                title: NSLocalizedString("MEASURE_STEP_COMPLETE_TITLE", comment: ""),
                description: NSLocalizedString("MEASURE_STEP_COMPLETE_DESC", comment: ""),
                icon: "checkmark.circle.fill"
            )
        }
    }
    
    var canCalculate: Bool {
        guard let diameter = Double(manualDiameter), diameter > 0 else { return false }
        guard let height = Double(manualHeight), height > 0 else { return false }
        return true
    }
    
    // MARK: - AR Session Management
    
    func configureARSession(_ session: ARSession) {
        self.arSession = session
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        isPlacingPoints = true
    }
    
    func pauseARSession() {
        arSession?.pause()
    }
    
    // MARK: - Measurement Logic
    
    func placePoint() {
        guard let session = arSession,
              let currentFrame = session.currentFrame else {
            return
        }
        
        // Get center point of screen in 3D space
        let screenCenter = CGPoint(x: 0.5, y: 0.5)
        
        if let raycastResult = performRaycast(from: screenCenter, frame: currentFrame) {
            let worldPosition = raycastResult.worldTransform.columns.3
            let point = SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z)
            
            measurementPoints.append(point)
            canReset = true
            
            // Update measurements based on current step
            switch currentStep {
            case .scanSurface:
                if measurementPoints.count >= 2 {
                    calculateDiameter()
                    currentStep = .measureDiameter
                }
            case .measureDiameter:
                if measurementPoints.count >= 3 {
                    calculateHeight()
                    currentStep = .measureHeight
                }
            case .measureHeight:
                if measurementPoints.count >= 4 {
                    finalizeMeasurement()
                }
            case .complete:
                break
            }
        }
    }
    
    private func performRaycast(from screenPoint: CGPoint, frame: ARFrame) -> ARRaycastResult? {
            // CORRECTION ICI : On utilise 'frame' pour créer la requête, pas 'arSession'
            let query = frame.raycastQuery(
                from: screenPoint,
                allowing: .estimatedPlane,
                alignment: .any
            )
            
            // Ensuite, on demande à la session d'exécuter ce raycast avec la requête créée
            let results = arSession?.raycast(query) ?? []
            return results.first
        }
    
    private func calculateDiameter() {
        guard measurementPoints.count >= 2 else { return }
        
        let point1 = measurementPoints[0]
        let point2 = measurementPoints[1]
        
        let distance = simd_distance(point1, point2)
        diameter = distance
        
        canPlacePoint = true
    }
    
    private func calculateHeight() {
        guard measurementPoints.count >= 3 else { return }
        
        let basePoint = measurementPoints[2]
        let topPoint = measurementPoints[measurementPoints.count - 1]
        
        let verticalDistance = abs(topPoint.y - basePoint.y)
        height = verticalDistance
        
        canPlacePoint = true
    }
    
    private func finalizeMeasurement() {
        guard let diameter = diameter,
              let height = height else {
            return
        }
        
        let diameterCm = Double(diameter * 100)
        let heightCm = Double(height * 100)
        
        currentMeasurement = PotMeasurement(
            diameter: diameterCm,
            height: heightCm,
            shape: selectedShape,
            material: selectedMaterial,
            drainageHoles: hasDrainage,
            notes: notes
        )
        
        currentStep = .complete
        isComplete = true
    }
    
    func calculateManualMeasurement(plantName: String?) {
        guard let diameter = Double(manualDiameter),
              let height = Double(manualHeight) else {
            return
        }
        
        currentMeasurement = PotMeasurement(
            plantName: plantName,
            diameter: diameter,
            height: height,
            shape: selectedShape,
            material: selectedMaterial,
            drainageHoles: hasDrainage,
            notes: notes
        )
    }
    
    func reset() {
        measurementPoints.removeAll()
        diameter = nil
        height = nil
        currentStep = .scanSurface
        isComplete = false
        canReset = false
        canPlacePoint = false
        currentMeasurement = nil
    }
}

// MARK: - ARSessionDelegate

extension ARMeasurementViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update canPlacePoint based on plane detection
        if !isComplete && currentStep != .complete {
            canPlacePoint = true
        }
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                currentPlaneAnchor = planeAnchor
            }
        }
    }
}

// MARK: - Supporting Types

enum MeasurementStep {
    case scanSurface
    case measureDiameter
    case measureHeight
    case complete
}

struct MeasurementInstruction {
    let title: String
    let description: String
    let icon: String
}
