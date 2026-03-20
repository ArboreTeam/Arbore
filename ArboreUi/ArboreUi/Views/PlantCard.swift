import SwiftUI

struct PlantCard: View {
    let plant: Plant
    @Environment(\.colorScheme) private var colorScheme

    private let cardHeight: CGFloat = 220

    // ⚠️ Remplace par ton URL backend réelle
    private let backendBaseURL = "http://79.137.92.154:8080"

    private var thumbnailURL: URL? {
        URL(string: "\(backendBaseURL)/models/thumbnails/\(plant.id).png")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                let size = geometry.size

                Group {
                    if let img = PlantThumbnailCache.load(for: plant.id) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()

                    } else if let url = thumbnailURL {
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

            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.8), Color.clear]),
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 80)

            Text(plant.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 4)
    }

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