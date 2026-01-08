import SwiftUI

struct HomeView: View {
    @State private var gardens: [GardenDTO] = []
    @State private var goToQuestionnaire = false
    @State private var goToAllGardens = false

    // ✅ On présente l’AR UNIQUEMENT si on a un jardin à ouvrir
    @State private var gardenToOpen: GardenDTO? = nil

    private let uid = "TEST_UID"

    private let background = Color(hex: "#F9F9F7")
    private let primary = Color(hex: "#8DBA8E")
    private let textDark = Color(hex: "#333333")
    private let textSubtle = Color(hex: "#63886f")
    private let cardLight = Color.white

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
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 44, height: 44)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

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
