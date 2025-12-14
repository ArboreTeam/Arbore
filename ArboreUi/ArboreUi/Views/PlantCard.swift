import SwiftUI

struct PlantCard: View {
    let plant: Plant
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            
            // 1. Image de fond qui remplit tout l'espace
            GeometryReader { geometry in
                if let firstURL = plant.imageURLs.first,
                   let url = URL(string: firstURL),
                   !firstURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill() // Important : remplit le cadre
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        case .failure:
                            fallbackImage
                        case .empty:
                            loadingView
                        @unknown default:
                            loadingView
                        }
                    }
                } else {
                    fallbackImage
                }
            }

            // 2. Dégradé sombre pour lisibilité
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.8), Color.clear]),
                startPoint: .bottom,
                endPoint: .top // Le dégradé monte un peu plus haut
            )
            .frame(height: 80) // Limite la hauteur du dégradé au bas de la carte

            // 3. Texte (Nom uniquement)
            Text(plant.name)
                .font(.system(size: 16, weight: .bold, design: .default)) // Taille ajustée pour la grille
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        // ✅ C'EST ICI QUE LA MAGIE OPÈRE
        .frame(minWidth: 0, maxWidth: .infinity) // Prend toute la largeur de la colonne
        .aspectRatio(0.8, contentMode: .fit) // Force un ratio portrait (largeur 1 / hauteur 1.25)
        .clipShape(RoundedRectangle(cornerRadius: 16)) // Arrondit les bords
        .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 4)
    }

    // Vues d'aide pour alléger le code principal
    var loadingView: some View {
        ZStack {
            Color(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color(hex: "#EAF1E7"))
            ProgressView()
        }
    }

    var fallbackImage: some View {
        ZStack {
            Color(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color(hex: "#EAF1E7"))
            Image(systemName: "leaf.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 40)
                .foregroundColor(Color(hex: "#263826").opacity(0.4))
        }
    }
}
