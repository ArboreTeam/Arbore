import SwiftUI

struct SanteDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // 🪰 Titre principal
                HStack {
                    Image(systemName: "ant.fill")
                        .foregroundColor(Color(hex: "#263826"))
                    Text("Ravageurs & maladies")
                        .font(.title2)
                        .bold()
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .padding(.horizontal)

                // 🐛 Types courants
                VStack(spacing: 16) {
                    InfoCardView(emoji: "🕷", title: "Araignées rouges", value: "Très petites, provoquent un jaunissement des feuilles.")
                    InfoCardView(emoji: "🦟", title: "Moucherons", value: "Attirés par l'humidité, pondent dans la terre.")
                    InfoCardView(emoji: "🪲", title: "Cochenilles", value: "Petites boules blanches ou brunes sur les tiges.")
                    InfoCardView(emoji: "🦠", title: "Champignons", value: "Taches brunes, moisissures, pourriture.")
                }
                .padding(.horizontal)

                // 💊 Traitement
                VStack(alignment: .leading, spacing: 12) {
                    Text("💊 Traitement naturel")
                        .font(.headline)
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Savon noir dilué (1 c. à soupe dans 1 L d'eau)")
                        Text("• Huile de neem en spray")
                        Text("• Aération + réduction de l'arrosage")
                        Text("• Rempotage si la terre est infestée")
                    }
                    .font(.subheadline)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                }
                .padding(.horizontal)

                // 🧰 Outils
                VStack(alignment: .leading, spacing: 12) {
                    Text("🧰 Outils suggérés")
                        .font(.headline)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.bottom, 4)

                    ToolCardView(icon: "camera.viewfinder", title: "Pest Scanner", description: "Scanne la plante pour détecter visuellement les nuisibles.")
                    ToolCardView(icon: "bandage.fill", title: "Guide de traitement", description: "Liste des traitements adaptés aux parasites détectés.")
                }
                .padding(.horizontal)
            }
            .padding(.top)
        }
        .navigationTitle("🦠 Santé")
        .navigationBarTitleDisplayMode(.inline)
        .background((colorScheme == .dark ? Color(hex: "#1A1A1A") : Color(hex: "#F1F5ED")).ignoresSafeArea())
    }
}
