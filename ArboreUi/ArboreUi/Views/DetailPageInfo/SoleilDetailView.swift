import SwiftUI

struct SoleilDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // 🌞 Titre principal
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(Color(hex: "#263826"))
                    Text("Détails sur le soleil")
                        .font(.title2)
                        .bold()
                }
                .padding(.horizontal)

                // 📋 Informations générales
                VStack(spacing: 16) {
                    InfoCardView(emoji: "☀️", title: "Exposition idéale", value: "Lumière vive indirecte")
                    InfoCardView(emoji: "🧭", title: "Orientation conseillée", value: "Fenêtre Est ou Ouest")
                    InfoCardView(emoji: "🌡️", title: "Température", value: "18°C à 25°C")
                    InfoCardView(emoji: "🚫", title: "À éviter", value: "Soleil direct brûlant (sud en été)")
                }
                .padding(.horizontal)

                // 🧪 Outils utiles
                VStack(alignment: .leading, spacing: 12) {
                    Text("🧰 Outils suggérés")
                        .font(.headline)
                        .padding(.bottom, 4)

                    ToolCardView(icon: "lightbulb", title: "Light Meter", description: "Mesure l’intensité lumineuse reçue.")
                    ToolCardView(icon: "location.north.line", title: "Compass", description: "Détermine l’orientation de vos fenêtres.")
                }
                .padding(.horizontal)
            }
            .padding(.top)
        }
        .navigationTitle("🌞 Soleil")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(hex: "#F1F5ED").ignoresSafeArea())
    }
}
