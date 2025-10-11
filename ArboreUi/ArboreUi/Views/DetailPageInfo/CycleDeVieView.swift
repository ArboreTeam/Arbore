import SwiftUI

struct CycleDeVieView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // 📅 Titre principal
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(Color(hex: "#263826"))
                    Text("Cycle de vie")
                        .font(.title2)
                        .bold()
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .padding(.horizontal)

                // 🌸 Floraison
                InfoCardView(emoji: "🌸", title: "Floraison", value: "De mars à juin. Certaines espèces peuvent refleurir à l'automne.")

                // 🌱 Croissance
                InfoCardView(emoji: "🌱", title: "Croissance", value: "Modérée à rapide selon les conditions (température, lumière, arrosage).")

                // 🌍 Origine
                InfoCardView(emoji: "🌍", title: "Origine", value: "Amérique du Sud, zones tropicales ou méditerranéennes.")

                // 📚 Infos statiques
                VStack(alignment: .leading, spacing: 12) {
                    Text("📚 Informations générales")
                        .font(.headline)
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Type de plante : Vivace ou annuelle")
                        Text("• Durée de vie moyenne : 3 à 10 ans")
                        Text("• Repos végétatif : Oui, en hiver (selon espèce)")
                    }
                    .font(.subheadline)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                }
                .padding(.horizontal)

            }
            .padding(.top)
        }
        .navigationTitle("📅 Cycle de vie")
        .navigationBarTitleDisplayMode(.inline)
        .background((colorScheme == .dark ? Color(hex: "#1A1A1A") : Color(hex: "#F1F5ED")).ignoresSafeArea())
    }
}
