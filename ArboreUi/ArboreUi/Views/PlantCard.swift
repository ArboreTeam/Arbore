import SwiftUI

struct PlantCard: View {
    let plant: Plant
    @State private var cachedThumbnail: UIImage?
    @State private var fetchedImage: UIImage?
    @State private var didFailLoading = false

    private let cardHeight: CGFloat = 220

    private let backendBaseURL = "http://79.137.92.154:8080"

    private var thumbnailURL: URL? {
        URL(string: "\(backendBaseURL)/models/thumbnails/\(plant.id).png")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                let size = geometry.size

                Group {
                    if let img = cachedThumbnail {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()

                    } else if let fetchedImage {
                        Image(uiImage: fetchedImage)
                            .resizable()
                            .scaledToFill()

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
            if plant.generated == true {
                betaBadge
                    .padding(10)
            }
        }
        .task(id: plant.id) {
            await loadRemoteThumbnailIfNeeded()
        }
    }

    private var betaBadge: some View {
        Text("BETA")
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

        // 2. Essaie de télécharger depuis le backend
        if let url = thumbnailURL {
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode),
                   let image = UIImage(data: data) {
                    await Task.detached(priority: .utility) {
                        PlantThumbnailCache.save(image, plantID: plant.id)
                    }.value
                    await MainActor.run {
                        cachedThumbnail = image
                        didFailLoading = false
                    }
                    return
                }
                // 404 ou autre erreur → passe au générateur local
            } catch {
                // Réseau indisponible → passe au générateur local
            }
        }

        // 3. Génère le thumbnail localement depuis le modèle USDZ
        await withCheckedContinuation { continuation in
            PlantThumbnailGenerator.shared.generateIfNeeded(plant: plant) { image in
                Task { @MainActor in
                    if let image {
                        self.cachedThumbnail = image
                        self.didFailLoading = false
                    } else {
                        self.didFailLoading = true
                    }
                    continuation.resume()
                }
            }
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
}
