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
    let measurementWorldMapId: String?

    // 🆕 Callback optionnel: appelé après validation AR pour fermer toute la pile
    var onCompleted: (() -> Void)? = nil

    @State private var showAR = false

    // permet de changer d'onglet après validation
    @EnvironmentObject private var tabRouter: TabRouter
    @Environment(\.presentationMode) private var presentationMode

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
        gardenName: String = L10n.t("MY_GARDEN_TITLE"),
        thumbnailKey: String? = nil,
        boundaryPoints: [SIMD3<Float>] = [],
        area: Float = 0.0,
        perimeter: Float = 0.0,
        measurementWorldMapId: String? = nil,
        onCompleted: (() -> Void)? = nil
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
        self.onCompleted = onCompleted
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.t("INTERMEDIATE_GARDEN_SAVED_TITLE"))
                .font(.title)
                .fontWeight(.bold)

            Text(L10n.t("INTERMEDIATE_GARDEN_SAVED_SUBTITLE"))
                .multilineTextAlignment(.center)
            
            // 🆕 Afficher les mesures
            if area > 0 {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "ruler")
                            .foregroundColor(.green)
                        Text(L10n.f("INTERMEDIATE_GARDEN_AREA_FORMAT", Double(area)))
                            .font(.subheadline)
                    }
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                            .foregroundColor(.green)
                        Text(L10n.f("INTERMEDIATE_GARDEN_PERIMETER_FORMAT", Double(perimeter)))
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }

            Button(L10n.t("INTERMEDIATE_GARDEN_CREATE")) {
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

                    // 3) Si un callback parent existe (ex: fermer ARViewContainerMesure aussi)
                    //    on l'appelle avec un léger délai pour laisser le dismiss se propager
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onCompleted?()
                        // 4) Aller sur l'onglet Accueil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            tabRouter.selectedTab = .home
                        }
                    }
                }
            )
        }
    }
}
