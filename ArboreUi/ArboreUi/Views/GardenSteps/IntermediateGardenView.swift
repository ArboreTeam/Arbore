import SwiftUI

struct IntermediateGardenView: View {
    let selectedPlants: [Plant]
    @State private var showAR = false

    init(selectedPlants: [Plant] = []) {
        self.selectedPlants = selectedPlants
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Mesures du jardin enregistrées")
                .font(.title).fontWeight(.bold)

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
            GardenARPlacementView(selectedPlants: selectedPlants)
        }
    }
}
