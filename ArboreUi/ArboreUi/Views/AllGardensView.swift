import SwiftUI

/// Écran "Voir tout" : affiche tous les jardins (même style que la Home),
/// et ouvre directement l’AR au tap sur une carte.
struct AllGardensView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    @State private var gardens: [GardenDTO] = []
    @State private var gardenToOpen: GardenDTO? = nil

    // Style dynamique via themeManager
    private var background: Color { themeManager.backgroundColor }
    private var primary: Color { themeManager.accentColor }
    private var textDark: Color { themeManager.textColor }
    private var textSubtle: Color { themeManager.secondaryTextColor }
    private var cardLight: Color { themeManager.cardBackgroundColor }

    // Arrondis (aligné Home “moelleux”)
    private let cardCorner: CGFloat = 28
    private let imageCorner: CGFloat = 24

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    topBar

                    if gardens.isEmpty {
                        emptyState
                    } else {
                        gardensList
                    }

                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
        .onAppear { Task { await fetchGardens() } }
        .preferredColorScheme(themeManager.colorScheme)
        .fullScreenCover(item: $gardenToOpen) { g in
            GardenARPlacementView(
                selectedPlants: [],
                uid: g.uid,
                wizard: g.wizard,
                gardenName: g.name,
                thumbnailKey: g.thumbnailKey,
                existingGardenId: g.id,
                mode: .reopen,
                boundaryPoints: [],  // Will be loaded from saved data
                area: 0,
                perimeter: 0,
                measurementWorldMapId: nil,  // Pas de mesure pour reopen
                onValidated: {
                    gardenToOpen = nil
                    Task { await fetchGardens() }
                }
            )
        }
    }
}

// MARK: - API
private extension AllGardensView {
    func fetchGardens() async {
        do {
            let list = try await GardenAPI.shared.listGardens()
            await MainActor.run { self.gardens = list }
        } catch {
            print("❌ fetchGardens failed:", error)
        }
    }
}

// MARK: - UI
private extension AllGardensView {

    /// Top bar alignée au style Home (typo serif + discret, bouton back “soft”)
    var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textDark)
                    .frame(width: 40, height: 40)
                    .background(themeManager.cardBackgroundColor.opacity(0.9))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 6)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Vos jardins")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundColor(textDark)

                Text("\(gardens.count) au total")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textSubtle.opacity(0.9))
            }

            Spacer()
        }
    }

    var emptyState: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Aucun jardin pour le moment")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textDark)

                Text("Vos jardins enregistrés apparaîtront ici.\nCommencez par en créer un nouveau.")
                    .font(.system(size: 14))
                    .foregroundColor(textSubtle)
            }
            Spacer()
            Image(systemName: "leaf")
                .font(.system(size: 28))
                .foregroundColor(primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(themeManager.cardBackgroundColor.opacity(0.7))
                )
        )
    }

    var gardensList: some View {
        VStack(spacing: 16) {
            ForEach(gardens.indices, id: \.self) { idx in
                gardenCard(garden: gardens[idx])
            }
        }
    }

    /// Card jardin alignée Home : image à hauteur fixe (plus compacte), coins bien arrondis, padding identique.
    func gardenCard(garden: GardenDTO) -> some View {
        Button {
            gardenToOpen = garden
        } label: {
            VStack(spacing: 0) {

                ZStack {
                    Image(garden.homeImageName)
                        .resizable()
                        .scaledToFill()
                        .allowsHitTesting(false)

                    LinearGradient(
                        colors: [Color.black.opacity(0.06), Color.black.opacity(0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                // ✅ IMPORTANT : même logique que Home → hauteur fixe
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: imageCorner, style: .continuous))
                .padding(.top, 12)
                .padding(.horizontal, 12)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(garden.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(textDark)

                        Text("\(garden.plants.count) plantes")
                            .font(.system(size: 13))
                            .foregroundColor(textSubtle)

                        if let d = garden.updatedAt {
                            Text("Dernière modification : \(d.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 12))
                                .foregroundColor(textSubtle.opacity(0.9))
                        }
                    }

                    Spacer()

                    Text("Ouvrir")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(primary)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(cardLight)
            .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Home image mapping
private extension GardenDTO {
    var homeImageName: String {
        let s = wizard.style
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        if s.contains("moderne") { return "modern-home" }
        if s.contains("fleuri") || s.contains("floral") { return "fleuri-home" }
        if s.contains("champetre") || s.contains("sauvage") { return "sauvage-home" }
        if s.contains("zen") || s.contains("japon") { return "zen-home" }
        if s.contains("mediterr") { return "mediterraneen-home" }

        return "modern-home"
    }
}
