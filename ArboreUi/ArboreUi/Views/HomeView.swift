import SwiftUI

struct HomeView: View {
    @State private var gardens: [GardenDTO] = []
    @State private var goToQuestionnaire = false
    @State private var goToAllGardens = false

    // ✅ On présente l’AR UNIQUEMENT si on a un jardin à ouvrir
    @State private var gardenToOpen: GardenDTO? = nil

    private let uid = "TEST_UID"

    // ✅ couleurs dynamiques (Light applique ta palette White)
    private let background = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
        ? UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
        : UIColor(red: 0.956, green: 0.953, blue: 0.937, alpha: 1.0) // #F4F3EF
    })

    private let cardLight = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
        ? UIColor(red: 0.13, green: 0.14, blue: 0.13, alpha: 1.0)
        : UIColor.white // #FFFFFF
    })

    private let separators = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
        ? UIColor(red: 0.18, green: 0.19, blue: 0.18, alpha: 1.0)
        : UIColor(red: 0.898, green: 0.890, blue: 0.867, alpha: 1.0) // #E5E3DD
    })

    private let textDark = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
        ? UIColor(white: 0.95, alpha: 1.0)
        : UIColor(red: 0.184, green: 0.184, blue: 0.184, alpha: 1.0) // #2F2F2F
    })

    private let textSubtle = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
        ? UIColor(white: 0.70, alpha: 1.0)
        : UIColor(red: 0.478, green: 0.478, blue: 0.478, alpha: 1.0) // #7A7A7A
    })

    private let primary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
        ? UIColor(red: 0.173, green: 0.333, blue: 0.188, alpha: 1.0) // #2C5530
        : UIColor(red: 0.553, green: 0.729, blue: 0.557, alpha: 1.0) // #8DBA8E
    })

    // ✅ MODIF: vert utilisé pour le texte sur bouton blanc ("Commencer")
    private let brandGreenTextOnWhite = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
        ? UIColor(red: 0.173, green: 0.333, blue: 0.188, alpha: 1.0) // #2C5530 (très lisible sur blanc)
        : UIColor(red: 0.388, green: 0.533, blue: 0.435, alpha: 1.0) // #63886F (ton ancien "textSubtle" vert)
    })

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        createGardenHero

                        // ✅ (Changement #2) : un peu plus d’air entre la card verte et "Vos jardins"
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
                    destination: AllGardensView(uid: uid),
                    isActive: $goToAllGardens,
                    label: { EmptyView() }
                )
                .hidden()
            }
            .navigationBarHidden(true)
            .onAppear {
                Task { await fetchGardens() }
            }
            // ✅ Présentation fiable (pas d’écran noir si gardenToOpen = nil)
            .fullScreenCover(item: $gardenToOpen) { g in
                GardenARPlacementView(
                    selectedPlants: [],
                    uid: g.uid,
                    wizard: g.wizard,
                    gardenName: g.name,
                    thumbnailKey: g.thumbnailKey,

                    // ✅ reopen
                    existingGardenId: g.id,     // si ton id est nil, ça ne chargera pas la worldmap
                    mode: .reopen,

                    onValidated: {
                        // ferme l’AR
                        gardenToOpen = nil
                        // refresh la home si besoin
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
            let list = try await GardenAPI.shared.listGardens(uid: uid)
            await MainActor.run {
                self.gardens = list
            }
        } catch {
            print("❌ fetchGardens failed:", error)
        }
    }
}

// MARK: - Header (refonte)
private extension HomeView {
    var header: some View {
        VStack(spacing: 6) {
            Text("Arbore")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundColor(textDark)

            Text("votre futur jardin")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(textSubtle.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

// MARK: - Card "Créer un futur jardin" (style Stitch)
private extension HomeView {
    var createGardenHero: some View {
        VStack(alignment: .leading, spacing: 12) { // ✅ (Changement #1) : spacing un peu réduit
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14)) // ✅ Option 2 : plus doux en dark
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .frame(width: 34, height: 34)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            // ✅ Option 1 : effet “badge” légèrement aligné au bord
            .padding(.top, -4)
            .padding(.leading, -2)

            Text("Créer un futur jardin")
                .font(.system(size: 22, weight: .bold, design: .serif))
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
                .foregroundColor(textSubtle) // effet “vert sombre”
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            NavigationLink(
                destination: GardenWizardView(
                    uid: uid,
                    selectedPlants: [],
                    onFinish: { _ in }
                ),
                isActive: $goToQuestionnaire,
                label: { EmptyView() }
            )
            .hidden()
        }
        .padding(.vertical, 18) // ✅ (Changement #1) : padding vertical réduit (moins “massif”)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(primary)
                .shadow(color: primary.opacity(0.18), radius: 18, x: 0, y: 10)
        )
    }
}

// MARK: - "Vos jardins" + Voir tout si > 2
private extension HomeView {
    var gardensTitle: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Vos jardins")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundColor(textDark)

            Spacer()

            if gardens.count > 2 {
                Button("Voir tout") {
                    goToAllGardens = true
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(textSubtle)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Empty state (inchangé)
private extension HomeView {
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
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                )
        )
    }
}

// MARK: - Liste des jardins existants (limite à 2)
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
            // ✅ ouvre directement l’AR
            gardenToOpen = garden
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    Image(garden.homeImageName)
                        .resizable()
                        .scaledToFill()
                        .allowsHitTesting(false) // ⚠️ OBLIGATOIRE

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

                    // ✅ (Changement #3) : bouton "Ouvrir" un poil plus discret/premium
                    Text("Ouvrir")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(primary.opacity(0.92))
                        .clipShape(Capsule())
                }
                .padding(16)
            }
            .background(cardLight)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
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
