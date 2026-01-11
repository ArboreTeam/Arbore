import SwiftUI

struct PlantCard: View {
    let plant: Plant
    @Environment(\.colorScheme) private var colorScheme

    /// Hauteur fixe pour stabiliser le layout dans les grilles (évite les chevauchements).
    private let cardHeight: CGFloat = 220

    var body: some View {
        ZStack(alignment: .bottomLeading) {

            // 1. IMAGE (thumbnail USDZ en priorité)
            GeometryReader { geometry in
                let size = geometry.size

                Group {
                    if let img = PlantThumbnailCache.load(for: plant.id) {
                        // ✅ Thumbnail généré depuis le modèle 3D
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()

                    } else if let firstURL = plant.imageURLs.first,
                              let url = URL(string: firstURL),
                              !firstURL.isEmpty {

                        // Fallback réseau (optionnel)
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
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
                .frame(width: size.width, height: size.height)
                .clipped()
            }

            // 2. Dégradé sombre (inchangé)
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.8), Color.clear]),
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 80)

            // 3. Texte (inchangé)
            Text(plant.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        // Layout global: taille stable dans le LazyVGrid
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 4)
    }

    // MARK: - Helpers

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
