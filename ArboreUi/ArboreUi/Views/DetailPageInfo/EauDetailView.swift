import SwiftUI

struct EauDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // 🔙 Titre principal
                HStack {
                    Image(systemName: "drop.fill")
                        .foregroundColor(Color(hex: "#263826"))
                    Text("Détails sur l’eau")
                        .font(.title2)
                        .bold()
                }
                .padding(.horizontal)

                // 💧 Cartes infos
                VStack(spacing: 16) {
                    InfoCardView(emoji: "💧", title: "Fréquence d’arrosage", value: "1 fois par semaine")
                    InfoCardView(emoji: "🌊", title: "Quantité", value: "Environ 200 mL par arrosage")
                    InfoCardView(emoji: "📆", title: "Période critique", value: "Printemps - Été")
                    InfoCardView(emoji: "⚠️", title: "À éviter", value: "Eau stagnante au fond du pot")
                }
                .padding(.horizontal)

                // 🧪 Outils suggérés
                VStack(alignment: .leading, spacing: 12) {
                    Text("🧰 Outils suggérés")
                        .font(.headline)
                        .padding(.bottom, 4)

                    ToolCardView(icon: "drop.triangle", title: "Water Calculator", description: "Estime la quantité d’eau idéale.")
                }
                .padding(.horizontal)
            }
            .padding(.top)
        }
        .navigationTitle("💧 Eau")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(hex: "#F1F5ED").ignoresSafeArea())
    }
}
