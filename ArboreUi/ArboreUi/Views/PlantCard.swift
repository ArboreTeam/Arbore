import SwiftUI

struct PlantCard: View {
    let plant: Plant
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    @State private var fetchedImage: UIImage?
    @State private var didFailLoading = false

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

                    } else if let fetchedImage {
                        Image(uiImage: fetchedImage)
                            .resizable()
                            .scaledToFill()

                    } else if let url = thumbnailURL, !didFailLoading {
                        loadingView

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
        .task(id: plant.id) {
            await loadRemoteThumbnailIfNeeded()
        }
    }

    private func loadRemoteThumbnailIfNeeded() async {
        await MainActor.run {
            didFailLoading = false
        }

        guard fetchedImage == nil else { return }
        guard PlantThumbnailCache.load(for: plant.id) == nil else { return }

        guard let url = thumbnailURL else { return }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    didFailLoading = true
                }
                return
            }

            await MainActor.run {
                fetchedImage = image
                didFailLoading = false
                PlantThumbnailCache.save(image, plantID: plant.id)
            }
        } catch {
            await MainActor.run {
                didFailLoading = true
            }
        }
    }

    var loadingView: some View {
        ZStack {
            themeManager.cardBackgroundColor
            ProgressView()
        }
    }

    var fallbackImage: some View {
        ZStack {
            themeManager.cardBackgroundColor
            Image(systemName: "leaf.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 40)
                .foregroundColor(themeManager.brandPrimary.opacity(0.4))
        }
    }
}