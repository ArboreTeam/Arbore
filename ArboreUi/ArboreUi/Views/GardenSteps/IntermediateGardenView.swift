import SwiftUI

struct IntermediateGardenView: View {
    let selectedPlants: [Plant]
    let uid: String

    // infos wizard
    let wizard: GardenWizardDTO
    let gardenName: String
    let thumbnailKey: String?
    
    // 🆕 Données de mesure du jardin
    let boundaryPoints: [SIMD3<Float>]
    let area: Float
    let perimeter: Float
    let measurementWorldMapId: String?  // 🆕 ID de la WorldMap sauvegardée lors de la mesure

    @State private var showAR = false

    // permet de changer d'onglet après validation
    @EnvironmentObject private var tabRouter: TabRouter
    @Environment(\.presentationMode) private var presentationMode  // 🆕 Pour fermer la vue

    init(
        selectedPlants: [Plant] = [],
        uid: String = "TEST_UID",
        wizard: GardenWizardDTO = GardenWizardDTO(
            style: "",
            spaceType: "",
            exposure: nil,
            maintenance: nil,
            safety: [],
            soil: nil,
            scanMethod: nil
        ),
        gardenName: String = "Mon jardin",
        thumbnailKey: String? = nil,
        boundaryPoints: [SIMD3<Float>] = [],
        area: Float = 0.0,
        perimeter: Float = 0.0,
        measurementWorldMapId: String? = nil
    ) {
        self.selectedPlants = selectedPlants
        self.uid = uid
        self.wizard = wizard
        self.gardenName = gardenName
        self.thumbnailKey = thumbnailKey
        self.boundaryPoints = boundaryPoints
        self.area = area
        self.perimeter = perimeter
        self.measurementWorldMapId = measurementWorldMapId
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Mesures du jardin enregistrées")
                .font(.title)
                .fontWeight(.bold)

            Text("Vous pouvez maintenant créer votre futur jardin.")
                .multilineTextAlignment(.center)
            
            // 🆕 Afficher les mesures
            if area > 0 {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "ruler")
                            .foregroundColor(.green)
                        Text("Surface: \(String(format: "%.2f", area)) m²")
                            .font(.subheadline)
                    }
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                            .foregroundColor(.green)
                        Text("Périmètre: \(String(format: "%.2f", perimeter)) m")
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }

            Button("Créer mon jardin") {
                showAR = true
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .background(Color.green)
            .cornerRadius(8)
        }
        .fullScreenCover(isPresented: $showAR) {
            GardenARPlacementView(
                selectedPlants: selectedPlants,
                uid: uid,
                wizard: wizard,
                gardenName: gardenName,
                thumbnailKey: thumbnailKey,

                // ✅ OBLIGATOIRE MAINTENANT
                existingGardenId: nil,
                mode: .create,
                
                // 🆕 Données de mesure
                boundaryPoints: boundaryPoints,
                area: area,
                perimeter: perimeter,
                measurementWorldMapId: measurementWorldMapId,  // 🆕 Pour charger la WorldMap

                onValidated: {
                    // 1) fermer l'AR
                    showAR = false

                    // 2) fermer IntermediateGardenView  
                    presentationMode.wrappedValue.dismiss()
                    
                    // 3) attendre un peu puis aller sur l'onglet Accueil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        tabRouter.selectedTab = .home
                    }
                }
            )
        }
    }
}
