import SwiftUI

struct PlantCard: View {
    let plant: Plant
    @State private var cachedThumbnail: UIImage?
    @State private var fetchedImage: UIImage?
    @State private var didFailLoading = false

    private let cardHeight: CGFloat = 220

    private var thumbnailURL: URL? {
        PlantThumbnailCache.remoteURL(for: plant.id, baseURL: AppConfig.baseURL)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                let size = geometry.size

                Group {
                    if let img = cachedThumbnail {
                        thumbnailImage(img)

                    } else if let fetchedImage {
                        thumbnailImage(fetchedImage)

                    } else if thumbnailURL != nil, !didFailLoading {
                        loadingView

                    } else {
                        fallbackImage
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }

            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.72),
                    Color.black.opacity(0.24),
                    Color.clear
                ]),
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 88)

            Text(plant.name)
                .font(ArboreDesign.Typography.cardTitle)
                .foregroundColor(.white)
                .lineLimit(1)
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .background(ArboreDesign.Colors.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: ArboreDesign.Colors.shadow, radius: 8, x: 0, y: 4)
        .overlay(alignment: .topTrailing) {
            if plant.source == "botanic" {
                botanicBadge
                    .padding(10)
            }
        }
        .task(id: plant.id) {
            await loadRemoteThumbnailIfNeeded()
        }
    }

    private var botanicBadge: some View {
        Text("BOTANIC")
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(ArboreDesign.Colors.primaryGreen)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                    )
            )
            .shadow(color: Color.black.opacity(0.22), radius: 2, x: 0, y: 1)
    }

    private func loadRemoteThumbnailIfNeeded() async {
        await MainActor.run { didFailLoading = false }

        // 1. Vérifie le cache disque local
        let diskImage = await Task.detached(priority: .userInitiated) {
            PlantThumbnailCache.load(for: plant.id)
        }.value

        if let img = diskImage {
            await MainActor.run { cachedThumbnail = img }
            return
        }

        // 2. Essaie le PNG pré-généré côté backend.
        if let url = thumbnailURL, let image = await downloadImage(from: url) {
            if PlantThumbnailCache.isLegacyThumbnail(image) {
                print("⚠️ Thumbnail distant legacy ignoré:", plant.id)
            } else {
                await displayAndCache(image)
                return
            }
        }

        // 3. If the backend PNG is unavailable, use the catalogue photo. The
        // customer-facing catalogue must never rebuild USDZ thumbnails on the
        // device: doing that for several visible cards is slow, battery-heavy,
        // and can make the phone noticeably hot. 3D generation stays confined
        // to the dedicated debug/admin screen used before uploading PNGs.
        if let rawURL = plant.imageURLs.first(where: { !$0.isEmpty }),
           let url = URL(string: rawURL),
           let image = await downloadImage(from: url) {
            await MainActor.run {
                fetchedImage = image
                didFailLoading = false
            }
            return
        }

        await MainActor.run {
            didFailLoading = true
        }
    }

    private func downloadImage(from url: URL) async -> UIImage? {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private func displayAndCache(_ image: UIImage) async {
        await MainActor.run {
            fetchedImage = image
            didFailLoading = false
        }

        let cachedImage = await Task.detached(priority: .utility) {
            PlantThumbnailCache.save(image, plantID: plant.id)
        }.value

        await MainActor.run {
            cachedThumbnail = cachedImage
        }
    }


    var loadingView: some View {
        ZStack {
            ArboreDesign.Colors.elevatedCard
            ProgressView()
                .tint(ArboreDesign.Colors.primaryGreen)
        }
    }

    var fallbackImage: some View {
        ZStack {
            ArboreDesign.Colors.elevatedCard

            VStack(spacing: ArboreDesign.Spacing.xs) {
                Image(systemName: "leaf")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(ArboreDesign.Colors.primaryGreen.opacity(0.6))

                Text("Arbore")
                    .font(ArboreDesign.Typography.caption)
                    .foregroundColor(ArboreDesign.Colors.textMuted)
            }
        }
    }

    private func thumbnailImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
    }
}
