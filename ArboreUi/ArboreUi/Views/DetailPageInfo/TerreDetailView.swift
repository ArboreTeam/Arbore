import SwiftUI

struct TerreDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // 🪴 Titre principal
                HStack {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(Color(hex: "#263826"))
                    Text("Détails sur la terre & le pot")
                        .font(.title2)
                        .bold()
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .padding(.horizontal)

                // 📋 Informations générales
                VStack(spacing: 16) {
                    InfoCardView(emoji: "🪴", title: "Taille du pot", value: "Adaptée à la taille des racines, avec 1–2 cm de marge")
                    InfoCardView(emoji: "🌱", title: "Type de sol", value: "Terreau universel ou spécifique (cactus, orchidée…)")
                    InfoCardView(emoji: "💧", title: "Drainage", value: "Trous de drainage indispensables + billes d'argile")
                    InfoCardView(emoji: "🧪", title: "pH idéal", value: "Souvent neutre (pH 6 à 7), sauf plantes acidophiles")
                }
                .padding(.horizontal)

                // 🧪 Outils utiles
                VStack(alignment: .leading, spacing: 12) {
                    Text("🧰 Outils suggérés")
                        .font(.headline)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.bottom, 4)

                    ToolCardView(icon: "ruler", title: "Pot Meter", description: "Aide à choisir la bonne taille de pot.")
                    ToolCardView(icon: "drop.triangle", title: "Soil Sensor", description: "Mesure le drainage et la rétention du sol.")
                }
                .padding(.horizontal)
            }
            .padding(.top)
        }
        .navigationTitle("🪴 Terre & Pot")
        .navigationBarTitleDisplayMode(.inline)
        .background((colorScheme == .dark ? Color(hex: "#1A1A1A") : Color(hex: "#F1F5ED")).ignoresSafeArea())
    }
}
