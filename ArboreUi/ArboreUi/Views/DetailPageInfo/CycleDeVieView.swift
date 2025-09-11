import SwiftUI

struct CycleDeVieView: View {
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
                }
                .padding(.horizontal)

                // 🌸 Floraison
                InfoCardView(emoji: "🌸", title: "Floraison", value: "De mars à juin. Certaines espèces peuvent refleurir à l’automne.")

                // 🌱 Croissance
                InfoCardView(emoji: "🌱", title: "Croissance", value: "Modérée à rapide selon les conditions (température, lumière, arrosage).")

                // 🌍 Origine
                InfoCardView(emoji: "🌍", title: "Origine", value: "Amérique du Sud, zones tropicales ou méditerranéennes.")

                // 📚 Infos statiques
                VStack(alignment: .leading, spacing: 12) {
                    Text("📚 Informations générales")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Type de plante : Vivace ou annuelle")
                        Text("• Durée de vie moyenne : 3 à 10 ans")
                        Text("• Repos végétatif : Oui, en hiver (selon espèce)")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)

            }
            .padding(.top)
        }
        .navigationTitle("📅 Cycle de vie")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(hex: "#F1F5ED").ignoresSafeArea())
    }
}
