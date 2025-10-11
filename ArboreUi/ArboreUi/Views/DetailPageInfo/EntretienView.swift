import SwiftUI

struct EntretienView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    // Exemple de conseils (à rendre dynamiques plus tard)
    let careTips: [String] = [
        "Nettoyer les feuilles régulièrement pour enlever la poussière.",
        "Surveiller l’apparition de parasites une fois par semaine.",
        "Tourner la plante d’un quart de tour toutes les deux semaines pour une croissance homogène.",
        "Rempoter tous les 1 à 2 ans selon la croissance.",
        "Utiliser un engrais naturel au printemps et en été."
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // 🧠 Titre principal
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(Color(hex: "#263826"))
                    Text("Entretien")
                        .font(.title2)
                        .bold()
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .padding(.horizontal)

                // 📋 Liste des conseils
                VStack(alignment: .leading, spacing: 12) {
                    Text("🧾 Astuces et bonnes pratiques")
                        .font(.headline)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    ForEach(careTips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hex: "#263826"))
                            Text(tip)
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .primary)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top)
        }
        .navigationTitle("🧠 Entretien")
        .navigationBarTitleDisplayMode(.inline)
        .background((colorScheme == .dark ? Color(hex: "#1A1A1A") : Color(hex: "#F1F5ED")).ignoresSafeArea())
    }
}
