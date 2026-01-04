import SwiftUI

struct IntermediateGardenView: View {
    let selectedPlants: [Plant]
    let uid: String

    // infos wizard
    let wizard: GardenWizardDTO
    let gardenName: String
    let thumbnailKey: String?

    @State private var showAR = false

    // permet de changer d’onglet après validation
    @EnvironmentObject private var tabRouter: TabRouter

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
        thumbnailKey: String? = nil
    ) {
        self.selectedPlants = selectedPlants
        self.uid = uid
        self.wizard = wizard
        self.gardenName = gardenName
        self.thumbnailKey = thumbnailKey
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Mesures du jardin enregistrées")
                .font(.title)
                .fontWeight(.bold)

            Text("Vous pouvez maintenant créer votre futur jardin.")
                .multilineTextAlignment(.center)

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

                onValidated: {
                    // 1) fermer l’AR
                    showAR = false

                    // 2) aller sur l’onglet Jardin
                    tabRouter.selectedTab = .garden
                }
            )
        }
    }
}
