import SwiftUI
import RoomPlan

struct LiDARScanWizardView: View {
    // Entrées du wizard
    let uid: String
    let selectedPlants: [Plant]
    let wizard: GardenWizardDTO
    let gardenName: String
    let thumbnailKey: String?
    let onSuccess: () -> Void
    
    // Callbacks
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var tabRouter: TabRouter
    
    // State LiDAR
    @State private var captureController = RoomCaptureController()
    @State private var isProcessing = false
    @State private var showARPlacement = false
    
    // Mesures extraites
    @State private var extractedArea: Float = 0.0
    @State private var extractedPerimeter: Float = 0.0
    // UUID pour la WorldMap et l'identification du jardin AR
    @State private var tempGardenId = UUID().uuidString
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            
            // Caméra LiDAR pleine vue
            CameraCaptureView()
                .environment(captureController)
                .ignoresSafeArea()
                .onAppear {
                    captureController.showSaveButton = false
                    captureController.isScanComplete = false
                    captureController.startSession()
                }
                .onDisappear {
                    captureController.stopSession()
                }
            
            // Interface
            VStack {
                // Header (bouton retour et titre)
                HStack(alignment: .top) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    
                    Spacer()
                    
                    VStack {
                        Text("Scan 3D")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Balayez les murs et l'espace de votre jardin/pièce.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Bouton invisible pour garder l'équilibre
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 24)
                .padding(.top, 50)
                
                Spacer()
                
                // Si l'utilisateur est dans la partie analyse post-scan
                if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Calcul des mesures...")
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .padding(.bottom, 50)
                } 
                // Bouton Terminé (si au moins une surface est détectée et bouton pas cliqué)
                else if captureController.showSaveButton {
                    Button(action: {
                        captureController.stopSession()
                        processScanAndContinue()
                    }) {
                        HStack {
                            Text("Scanner le jardin terminé")
                            Image(systemName: "checkmark")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 24)
                        .background(Color.blue)
                        .cornerRadius(30)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(isPresented: $showARPlacement) {
            GardenARPlacementView(
                selectedPlants: selectedPlants,
                uid: uid,
                wizard: wizard,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,
                existingGardenId: nil,
                mode: .create,
                boundaryPoints: [], // Pas de tracer au sol en 3D
                area: extractedArea,
                perimeter: extractedPerimeter,
                measurementWorldMapId: tempGardenId,
                onValidated: {
                    showARPlacement = false
                    tabRouter.selectedTab = .home
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        onSuccess()
                    }
                }
            )
        }
    }
    
    private func processScanAndContinue() {
        isProcessing = true
        
        // 1. Sauvegarder la WorldMap pour AR (comme dans ARViewContainerMeasure)
        print("🗺️ LiDAR: Sauvegarde WorldMap pour AR Placement avec ID \(tempGardenId)")
        captureController.roomCaptureView.captureSession.arSession.getCurrentWorldMap { worldMap, error in
            if let map = worldMap {
                do {
                    let mapData = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                    let url = GardenLocalStore.worldMapURL(for: tempGardenId)
                    try mapData.write(to: url)
                    print("✅ WorldMap LiDAR sauvegardée")
                } catch {
                    print("❌ Erreur sauvegarde WorldMap LiDAR: \(error)")
                }
            }
            
            // 2. Extraire Surface et Périmètre
            var area: Float = 0.0
            var perimeter: Float = 0.0
            
            if let room = captureController.finalResult {
                // Surface: somme de la surface de chaque partie de "Sol"
                for floor in room.floors {
                    area += Float(floor.dimensions.x * floor.dimensions.y)
                }
                
                // Périmètre: somme de la longueur des murs (approximation)
                for wall in room.walls {
                    perimeter += Float(wall.dimensions.x) // dimensions.x est la largeur du mur
                }
            }
            
            // Sécurité si aucune surface de sol n'a été détectée
            if area == 0 {
                area = 10.0 // Valeur par défaut
                perimeter = 12.6
            }
            
            self.extractedArea = area
            self.extractedPerimeter = perimeter
            
            print("📐 LiDAR: Surface calculée \(area) m², Périmètre \(perimeter) m")
            
            // 3. Ouvrir l'AR Placement avec un petit délai
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isProcessing = false
                showARPlacement = true
            }
        }
    }
}
