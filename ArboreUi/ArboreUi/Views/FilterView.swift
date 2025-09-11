import SwiftUI

struct FilterView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedLight: String? = nil
    @State private var selectedWater: String? = nil
    @State private var selectedDifficulty: String? = nil

    let lightOptions = ["Faible", "Modérée", "Forte"]
    let waterOptions = ["Peu", "Moyen", "Souvent"]
    let difficultyOptions = ["Facile", "Intermédiaire", "Exigeante"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Section lumière
                Text("Luminosité")
                    .font(.headline)
                    .foregroundColor(Color(hex: "#263826"))
                HStack {
                    ForEach(lightOptions, id: \.self) { option in
                        FilterChip(title: option, isSelected: selectedLight == option) {
                            selectedLight = selectedLight == option ? nil : option
                        }
                    }
                }

                // Section eau
                Text("Arrosage")
                    .font(.headline)
                    .foregroundColor(Color(hex: "#263826"))
                HStack {
                    ForEach(waterOptions, id: \.self) { option in
                        FilterChip(title: option, isSelected: selectedWater == option) {
                            selectedWater = selectedWater == option ? nil : option
                        }
                    }
                }

                // Section entretien
                Text("Entretien")
                    .font(.headline)
                    .foregroundColor(Color(hex: "#263826"))
                HStack {
                    ForEach(difficultyOptions, id: \.self) { option in
                        FilterChip(title: option, isSelected: selectedDifficulty == option) {
                            selectedDifficulty = selectedDifficulty == option ? nil : option
                        }
                    }
                }

                Spacer()

                Button(action: {
                    // Appliquer les filtres ici si connecté à un backend
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Appliquer les filtres")
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(hex: "#263826"))
                        .cornerRadius(12)
                }
            }
            .padding()
            .background(Color(hex: "#F1F5ED").ignoresSafeArea())
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color(hex: "#263826") : Color.white)
                .foregroundColor(isSelected ? .white : .black)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(hex: "#263826"), lineWidth: 1)
                )
                .cornerRadius(20)
        }
    }
}
