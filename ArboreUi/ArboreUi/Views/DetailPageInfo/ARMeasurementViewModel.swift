import SwiftUI
import ARKit
import RealityKit
import Combine
import SceneKit

// MARK: - AR Measurement ViewModel

class ARMeasurementViewModel: NSObject, ObservableObject {
    
    // MARK: - Published Properties (UI)
    @Published var isPlacingPoints = false
    @Published var canPlacePoint = false
    @Published var canReset = false
    @Published var isComplete = false
    
    @Published var diameter: Float?
    @Published var height: Float?
    @Published var currentStep: MeasurementStep = .scanSurface
    
    // Valeur en temps réel pour l'affichage pendant la mesure (feedback visuel)
    @Published var realtimeLineValue: Float = 0
    
    // --- Entrées Manuelles ---
    @Published var currentMeasurement: PotMeasurement?
    @Published var manualDiameter: String = ""
    @Published var manualHeight: String = ""
    @Published var selectedShape: PotShape = .round
    @Published var selectedMaterial: PotMaterial? = nil
    @Published var hasDrainage: Bool = true
    @Published var notes: String = ""
    
    // MARK: - Internal Properties
    var arSession: ARSession?
    var sceneView: ARSCNView? // Référence pour les calculs 3D
    
    // MARK: - Private Logic Properties
    private var diameterStartPoint: SIMD3<Float>?
    private var heightBasePoint: SIMD3<Float>?
    private var reticlePosition: SIMD3<Float>? // Position visée actuelle
    
    // Nœud du viseur 3D
    private var reticleNode: SCNNode?
    
    // MARK: - Computed Properties
    
    var currentInstruction: MeasurementInstruction {
        switch currentStep {
        case .scanSurface:
            return MeasurementInstruction(
                title: NSLocalizedString("MEASURE_STEP_SCAN_TITLE", comment: "Scan"),
                description: "Bougez l'appareil pour détecter le sol",
                icon: "camera.metering.center.weighted"
            )
        case .measureDiameter:
            return MeasurementInstruction(
                title: NSLocalizedString("MEASURE_STEP_DIAMETER_TITLE", comment: "Diamètre"),
                description: diameterStartPoint == nil ? "Placez le premier point au bord" : "Placez le second point à l'opposé",
                icon: "arrow.left.and.right"
            )
        case .measureHeight:
            return MeasurementInstruction(
                title: NSLocalizedString("MEASURE_STEP_HEIGHT_TITLE", comment: "Hauteur"),
                description: heightBasePoint == nil ? "Touchez le sol à la base du pot" : "Levez le téléphone jusqu'au haut du pot",
                icon: "arrow.up.and.down"
            )
        case .complete:
            return MeasurementInstruction(
                title: NSLocalizedString("MEASURE_STEP_COMPLETE_TITLE", comment: "Fini"),
                description: "Mesures terminées !",
                icon: "checkmark.circle.fill"
            )
        }
    }
    
    var canCalculate: Bool {
        guard let d = Double(manualDiameter), d > 0, let h = Double(manualHeight), h > 0 else { return false }
        return true
    }
    
    // MARK: - Setup UI 3D
    
    // Création du viseur (appelé automatiquement par updateLoop)
    private func setupReticle() {
        guard let sceneView = sceneView else { return }
        
        // On crée un plan de 5cm x 5cm pour le viseur
        let planeGeometry = SCNPlane(width: 0.05, height: 0.05)
        let material = SCNMaterial()
        
        // Utilisation d'une icône système SF Symbol pour le viseur
        // On crée une configuration pour avoir un trait un peu épais
        let config = UIImage.SymbolConfiguration(pointSize: 50, weight: .bold)
        
        // "viewfinder" est l'icône parfaite pour ça (carré avec coins)
        if let image = UIImage(systemName: "viewfinder", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            material.diffuse.contents = image
        } else {
            // Fallback si l'image charge pas : carré blanc semi-transparent
            material.diffuse.contents = UIColor.white.withAlphaComponent(0.8)
        }
        
        material.isDoubleSided = true
        material.blendMode = .alpha // Important pour la transparence du PNG
        
        planeGeometry.materials = [material]
        
        reticleNode = SCNNode(geometry: planeGeometry)
        
        // Par défaut à plat sur le sol (-90 degrés sur X)
        reticleNode?.eulerAngles.x = -.pi / 2
        reticleNode?.isHidden = true
        
        sceneView.scene.rootNode.addChildNode(reticleNode!)
    }
    
    // MARK: - Update Loop (Coeur du système)
    
    // Appelée 60x par seconde depuis le Coordinator
    func updateLoop(cameraTransform: simd_float4x4) {
        guard let sceneView = sceneView else { return }
        
        // Initialiser le réticule si nécessaire
        if reticleNode == nil {
            setupReticle()
        }
        
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        
        // 1. Raycast Sol Standard
        let query = sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any)
        let raycastResults = query.map { sceneView.session.raycast($0) } ?? []
        
        var detectedPoint: SIMD3<Float>? = nil
        var isVerticalMode = false
        
        // --- LOGIQUE DE DÉTECTION ---
        
        // Cas : Mesure de HAUTEUR (Une fois la base posée)
        // On projette sur un plan vertical imaginaire
        if currentStep == .measureHeight, let basePoint = heightBasePoint {
            isVerticalMode = true
            
            // Position et direction caméra
            let cameraPos = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
            // Vecteur Forward de la caméra (colonne 2 inversée)
            let forwardVector = -SIMD3<Float>(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
            
            // Calcul de la normale du plan vertical
            // Le plan passe par basePoint et fait face à la caméra
            let vectorToBase = basePoint - cameraPos
            let planeNormal = normalize(SIMD3<Float>(vectorToBase.x, 0, vectorToBase.z))
            
            // Intersection Ligne (Caméra) vs Plan
            let numerator = dot((basePoint - cameraPos), planeNormal)
            let denominator = dot(forwardVector, planeNormal)
            
            if abs(denominator) > 0.001 {
                let t = numerator / denominator
                if t > 0 {
                    let intersectionPoint = cameraPos + (forwardVector * t)
                    detectedPoint = intersectionPoint
                    
                    // Feedback temps réel
                    self.realtimeLineValue = abs(intersectionPoint.y - basePoint.y)
                }
            }
        }
        // Cas : Standard (Sol)
        else if let result = raycastResults.first {
            detectedPoint = SIMD3<Float>(result.worldTransform.columns.3.x, result.worldTransform.columns.3.y, result.worldTransform.columns.3.z)
            
            if currentStep == .scanSurface {
                currentStep = .measureDiameter
            }
        }
        
        // --- MISE À JOUR VISUELLE ---
        
        if let point = detectedPoint {
            self.reticlePosition = point
            self.canPlacePoint = true
            
            reticleNode?.isHidden = false
            reticleNode?.position = SCNVector3(point.x, point.y, point.z)
            
            // Feedback visuel sur le réticule
            if isVerticalMode {
                // En mode hauteur, on le teint en VERT
                reticleNode?.geometry?.firstMaterial?.diffuse.contents = UIColor.green.withAlphaComponent(0.8)
                // On le laisse à plat (-pi/2) pour faire comme un niveau laser
                reticleNode?.eulerAngles.x = -.pi / 2
            } else {
                // Au sol, BLANC
                // On recrée l'image blanche si besoin, ou juste couleur
                // Pour simplifier, on remet blanc
                reticleNode?.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.9)
                reticleNode?.eulerAngles.x = -.pi / 2
            }
            
        } else {
            self.canPlacePoint = false
            reticleNode?.isHidden = true
        }
    }
    
    // MARK: - Actions Utilisateur
    
    func placePoint() {
        guard let currentPos = reticlePosition else { return }
        
        switch currentStep {
        case .scanSurface:
            currentStep = .measureDiameter
            
        case .measureDiameter:
            if diameterStartPoint == nil {
                // Point A Diamètre
                diameterStartPoint = currentPos
                addDot(at: currentPos, color: .orange)
                canReset = true
            } else {
                // Point B Diamètre
                guard let start = diameterStartPoint else { return }
                self.diameter = simd_distance(start, currentPos)
                addDot(at: currentPos, color: .orange)
                
                // Passage à la hauteur
                currentStep = .measureHeight
                canPlacePoint = true
            }
            
        case .measureHeight:
            if heightBasePoint == nil {
                // Point A Hauteur (Base)
                heightBasePoint = currentPos
                addDot(at: currentPos, color: .green)
            } else {
                // Point B Hauteur (Haut)
                guard let base = heightBasePoint else { return }
                
                // Calcul purement vertical (Y)
                self.height = abs(currentPos.y - base.y)
                addDot(at: currentPos, color: .green)
                
                finalizeMeasurement()
            }
            
        case .complete:
            break
        }
    }
    
    func reset() {
        diameterStartPoint = nil
        heightBasePoint = nil
        diameter = nil
        height = nil
        currentStep = .scanSurface
        isComplete = false
        canReset = false
        currentMeasurement = nil
        
        // Nettoyage scène
        sceneView?.scene.rootNode.enumerateChildNodes { (node, _) in
            if node.name == "MeasurementDot" { node.removeFromParentNode() }
        }
        reticleNode?.isHidden = true
    }
    
    // MARK: - Helpers
    
    private func addDot(at position: SIMD3<Float>, color: UIColor) {
        guard let sceneView = sceneView else { return }
        
        let sphere = SCNSphere(radius: 0.01) // 1cm
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.emission.contents = color // Pour que ça brille un peu
        
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(position.x, position.y, position.z)
        node.name = "MeasurementDot"
        
        sceneView.scene.rootNode.addChildNode(node)
    }
    
    private func finalizeMeasurement() {
        guard let d = diameter, let h = height else { return }
        
        currentMeasurement = PotMeasurement(
            diameter: Double(d * 100),
            height: Double(h * 100),
            shape: selectedShape,
            material: selectedMaterial,
            drainageHoles: hasDrainage,
            notes: notes
        )
        isComplete = true
        currentStep = .complete
    }
    
    func calculateManualMeasurement(plantName: String?) {
        guard let d = Double(manualDiameter), let h = Double(manualHeight) else { return }
        currentMeasurement = PotMeasurement(
            plantName: plantName,
            diameter: d,
            height: h,
            shape: selectedShape,
            material: selectedMaterial,
            drainageHoles: hasDrainage,
            notes: notes
        )
    }
    
    // Math utils
    func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        return a.x * b.x + a.y * b.y + a.z * b.z
    }
    
    func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let length = sqrt(dot(v, v))
        return length == 0 ? v : v / length
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
