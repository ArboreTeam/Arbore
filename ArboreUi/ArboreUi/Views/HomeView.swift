import SwiftUI
import FirebaseAuth

struct HomeView: View {
    @State private var gardens: [GardenDTO] = []
    @State private var goToQuestionnaire = false
    @State private var goToAllGardens = false
    @EnvironmentObject var themeManager: ThemeManager

    @State private var gardenToOpen: GardenDTO? = nil

    // Real Firebase UID — used when starting the garden creation wizard so
    // the created garden is scoped to the currently signed-in user.
    private var currentUID: String { Auth.auth().currentUser?.uid ?? "" }

    // Fond beige signature de la Home (conservé intentionnellement pour l'identité de page)
    private let homeBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
        ? UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
        : UIColor(red: 0.956, green: 0.953, blue: 0.937, alpha: 1.0) // #F4F3EF
    })

    var body: some View {
        NavigationStack {
            ZStack {
                homeBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        createGardenHero

                        Spacer(minLength: 6)

                        gardensTitle

                        if gardens.isEmpty {
                            emptyState
                        } else {
                            gardensList
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }

                NavigationLink(
                    destination: AllGardensView(),
                    isActive: $goToAllGardens,
                    label: { EmptyView() }
                )
                .hidden()
            }
            .navigationBarHidden(true)
            .onAppear {
                Task { await fetchGardens() }
            }
            .fullScreenCover(item: $gardenToOpen) { g in
                GardenARPlacementView(
                    selectedPlants: [],
                    uid: g.uid,
                    wizard: g.wizard,
                    gardenName: g.name,
                    thumbnailKey: g.thumbnailKey,
                    existingGardenId: g.id,
                    mode: .reopen,
                    boundaryPoints: [],
                    area: 0,
                    perimeter: 0,
                    measurementWorldMapId: nil,
                    onValidated: {
                        gardenToOpen = nil
                        Task { await fetchGardens() }
                    }
                )
            }
        }
    }
}

// MARK: - API
private extension HomeView {
    func fetchGardens() async {
        do {
            let list = try await GardenAPI.shared.listGardens()
            await MainActor.run {
                self.gardens = list
            }
        } catch {
            print("❌ fetchGardens failed:", error)
        }
    }
}

// MARK: - Header
private extension HomeView {
    var header: some View {
        VStack(spacing: 6) {
            Text("Arbore")
                .font(themeManager.pageTitle(size: 34))
                .foregroundColor(themeManager.textColor)

            Text("votre futur jardin")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(themeManager.secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

// MARK: - Card "Créer un futur jardin"
private extension HomeView {
    var createGardenHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .frame(width: 34, height: 34)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.top, -4)
            .padding(.leading, -2)

            Text("Créer un futur jardin")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Commencez la conception étape par étape\npour donner vie à vos idées.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineSpacing(2)

            Button {
                goToQuestionnaire = true
            } label: {
                HStack(spacing: 10) {
                    Text("Commencer")
                        .font(.system(size: 15, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(themeManager.brandPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            NavigationLink(
                destination: GardenWizardView(
                    uid: currentUID,
                    selectedPlants: [],
                    onFinish: { _ in }
                ),
                isActive: $goToQuestionnaire,
                label: { EmptyView() }
            )
            .hidden()
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(themeManager.heroCornerRadius), style: .continuous)
                .fill(themeManager.brandPrimaryHero)
                .shadow(color: themeManager.brandPrimaryHero.opacity(0.20), radius: 18, x: 0, y: 10)
        )
    }
}

// MARK: - "Vos jardins" + Voir tout
private extension HomeView {
    var gardensTitle: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Vos jardins")
                .font(themeManager.sectionTitle(size: 22))
                .foregroundColor(themeManager.textColor)

            Spacer()

            if gardens.count > 2 {
                Button("Voir tout") {
                    goToAllGardens = true
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(themeManager.secondaryTextColor)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Empty state
private extension HomeView {
    var emptyState: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Aucun jardin pour le moment")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.textColor)

                Text("Vos jardins enregistrés apparaîtront ici.\nCommencez par en créer un nouveau.")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            Spacer()
            Image(systemName: "leaf")
                .font(.system(size: 28))
                .foregroundColor(themeManager.brandPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(themeManager.heroCornerRadius), style: .continuous)
                .strokeBorder(Color.gray.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(themeManager.cardBackgroundColor.opacity(0.7))
                )
        )
    }
}

// MARK: - Liste des jardins (limite à 2)
private extension HomeView {
    var gardensList: some View {
        let preview = Array(gardens.prefix(2))
        return VStack(spacing: 16) {
            ForEach(preview.indices, id: \.self) { idx in
                gardenCard(garden: preview[idx])
            }
        }
    }

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
                        colors: [Color.black.opacity(0.08), Color.black.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .frame(height: 220)
                .clipped()

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(garden.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)

                        Text("\(garden.plants.count) plantes")
                            .font(.system(size: 13))
                            .foregroundColor(themeManager.secondaryTextColor)

                        if let d = garden.updatedAt {
                            Text("Dernière modification : \(d.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.secondaryTextColor.opacity(0.9))
                        }
                    }

                    Spacer()

                    Text("Ouvrir")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(themeManager.brandPrimary.opacity(0.92))
                        .clipShape(Capsule())
                }
                .padding(16)
            }
            .background(themeManager.cardBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(themeManager.heroCornerRadius), style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

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
