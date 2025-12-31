import SwiftUI

struct PlantCard: View {
    let plant: Plant
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomLeading) {

            // 1. IMAGE (thumbnail USDZ en priorité)
            GeometryReader { geometry in
                if let img = PlantThumbnailCache.load(for: plant.id) {
                    // ✅ Thumbnail généré depuis le modèle 3D
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

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
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                } else {
                    fallbackImage
                }
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
        // Layout global (inchangé)
        .frame(minWidth: 0, maxWidth: .infinity)
        .aspectRatio(0.8, contentMode: .fit)
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
