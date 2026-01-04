import SwiftUI

struct HomeView: View {
    @State private var gardens: [GardenDTO] = []
    @State private var goToQuestionnaire = false

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
                    VStack(spacing: 24) {
                        header
                        createGardenHero
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

// MARK: - Header
private extension HomeView {
    var header: some View {
        VStack(spacing: 8) {
            Text("Arbore")
                .font(.system(size: 36, weight: .bold, design: .serif))
                .foregroundColor(textDark)
                .multilineTextAlignment(.center)

            Text("Imaginez et visualisez\nvotre futur jardin")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(textSubtle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

private extension HomeView {
    var createGardenHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(primary.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: "leaf.fill")
                        .font(.system(size: 22))
                        .foregroundColor(primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Créer un futur jardin")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(textDark)

                    Text("Commencez la conception étape par étape.")
                        .font(.system(size: 15))
                        .foregroundColor(textSubtle)
                }
            }

            Button {
                goToQuestionnaire = true
            } label: {
                Text("Commencer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
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
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardLight)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - "Vos jardins"
private extension HomeView {
    var gardensTitle: some View {
        HStack {
            Text("Vos jardins")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(textDark)
            Spacer()
        }
        .padding(.top, 8)
    }
}

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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                )
        )
    }
}

// MARK: - Liste des jardins existants
private extension HomeView {
    var gardensList: some View {
        VStack(spacing: 16) {
            ForEach(gardens.indices, id: \.self) { idx in
                gardenCard(garden: gardens[idx])
            }
        }
    }

    func gardenCard(garden: GardenDTO) -> some View {
        Button {
            // ✅ ça ouvre directement l’AR, sans bool séparé
            gardenToOpen = garden
        } label: {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color(hex: "#2F5136"), Color(hex: "#4F7B54")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "leaf.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white.opacity(0.12))
                        .padding(30)
                )
                .frame(height: 140)

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
                .padding(16)
            }
            .background(cardLight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}
