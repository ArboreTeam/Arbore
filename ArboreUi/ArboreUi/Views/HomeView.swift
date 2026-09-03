import SwiftUI
import FirebaseAuth

struct HomeView: View {
    @State private var gardens: [GardenDTO] = []
    @State private var goToQuestionnaire = false
    @State private var goToAllGardens = false
    @State private var showChat = false
    @EnvironmentObject var themeManager: ThemeManager

    @State private var gardenToOpen: GardenDTO? = nil

    // Real Firebase UID — used when starting the garden creation wizard so
    // the created garden is scoped to the currently signed-in user.
    private var currentUID: String { Auth.auth().currentUser?.uid ?? "" }

    var body: some View {
        NavigationStack {
            AppBackground {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: ArboreDesign.Spacing.xl) {
                        header
                        createGardenHero
                        gardensHeader

                        if gardens.isEmpty {
                            emptyState
                        } else {
                            gardensList
                        }

                        Spacer(minLength: ArboreDesign.Spacing.md)
                    }
                    .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
                    .padding(.top, ArboreDesign.Spacing.md)
                    .padding(.bottom, 110)
                }

                Color.clear
                    .frame(width: 0, height: 0)
                    .navigationDestination(isPresented: $goToAllGardens) {
                        AllGardensView()
                    }
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
            .fullScreenCover(isPresented: $showChat) {
                ChatBotView(showsDismissButton: true)
                    .environmentObject(themeManager)
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
            // #391 — un invité n'a pas accès à /gardens. Sans ce cas, la liste
            // restait simplement vide : l'utilisateur lisait « aucun jardin »
            // là où la vraie raison était l'absence de compte.
            if error.isAccountRequired {
                await MainActor.run { self.gardens = [] }
                return
            }
            print("❌ fetchGardens failed:", error)
        }
    }
}

// MARK: - Header
private extension HomeView {
    var header: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
            HStack(alignment: .center, spacing: ArboreDesign.Spacing.md) {
                Text("Arbore")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Spacer(minLength: ArboreDesign.Spacing.sm)

                chatButton
            }

            Text(L10n.t("HOME_SUBTITLE"))
                .font(ArboreDesign.Typography.bodySmall)
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var chatButton: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Button {
                showChat = true
            } label: {
                chatButtonLabel
            }
            .buttonStyle(.glass)
        } else {
            Button {
                showChat = true
            } label: {
                chatButtonLabel
            }
            .buttonStyle(.bordered)
        }
        #else
        Button {
            showChat = true
        } label: {
            chatButtonLabel
        }
        .buttonStyle(.bordered)
        #endif
    }

    var chatButtonLabel: some View {
        Image(systemName: "bubble.left.and.text.bubble.right.fill")
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 28, height: 28)
            .accessibilityLabel("Ouvrir le Chat")
    }
}

// MARK: - Card "Créer un futur jardin"
private extension HomeView {
    var createGardenHero: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
            HStack(alignment: .top, spacing: ArboreDesign.Spacing.md) {
                SettingsIconBadge(systemImage: "leaf.fill", tint: ArboreDesign.Colors.primaryGreen, size: 44)

                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                    Text(L10n.t("HOME_CREATE_GARDEN_TITLE"))
                        .font(ArboreDesign.Typography.sectionTitle)
                        .foregroundColor(ArboreDesign.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.t("HOME_CREATE_GARDEN_SUBTITLE"))
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                // #393 — le gate invité est levé. Il existait parce que le
                // wizard pré-crée le jardin en base à l'étape scan et que
                // `POST /gardens` répondait alors 403 à un invité : l'échec
                // serait tombé après le questionnaire ET le tracé AR du
                // périmètre, soit plusieurs minutes perdues.
                //
                // La route est désormais ouverte aux sessions anonymes, le
                // parcours aboutit donc. Un invité qui crée ensuite un compte
                // repart en revanche de zéro, `linkWithCredential` n'existant
                // pas encore (#391, section 4).
                goToQuestionnaire = true
            } label: {
                HStack(spacing: 10) {
                    Text(L10n.t("COMMON_START"))
                        .font(ArboreDesign.Typography.button)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(ArboreDesign.Colors.primaryButton)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)

            Color.clear
                .frame(width: 0, height: 0)
                .navigationDestination(isPresented: $goToQuestionnaire) {
                    GardenWizardView(
                        uid: currentUID,
                        selectedPlants: [],
                        onFinish: { _ in }
                    )
                }
        }
        .padding(ArboreDesign.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
        .shadow(color: ArboreDesign.Colors.shadow, radius: 10, x: 0, y: 4)
    }
}

// MARK: - "Vos jardins" + Voir tout
private extension HomeView {
    var gardensHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(L10n.t("HOME_YOUR_GARDENS"))
                .font(ArboreDesign.Typography.sectionTitle)
                .foregroundColor(ArboreDesign.Colors.textPrimary)

            Spacer()

            if gardens.count > 2 {
                Button(L10n.t("COMMON_SEE_ALL")) {
                    goToAllGardens = true
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ArboreDesign.Colors.primaryGreen)
            }
        }
    }
}

// MARK: - Empty state
private extension HomeView {
    var emptyState: some View {
        AppCard {
            HStack(spacing: ArboreDesign.Spacing.md) {
                SettingsIconBadge(systemImage: "leaf", tint: ArboreDesign.Colors.primaryGreen, size: 44)

                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                    Text(L10n.t("HOME_EMPTY_TITLE"))
                        .font(ArboreDesign.Typography.cardTitle)
                        .foregroundColor(ArboreDesign.Colors.textPrimary)

                    Text(L10n.t("HOME_EMPTY_SUBTITLE"))
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Liste des jardins (limite à 2)
private extension HomeView {
    var gardensList: some View {
        let preview = Array(gardens.prefix(2))
        return VStack(spacing: ArboreDesign.Spacing.md) {
            ForEach(preview.indices, id: \.self) { idx in
                gardenCard(garden: preview[idx])
            }
        }
    }

    func gardenCard(garden: GardenDTO) -> some View {
        Button {
            gardenToOpen = garden
        } label: {
            VStack(spacing: ArboreDesign.Spacing.sm) {
                ZStack {
                    Image(garden.homeImageName)
                        .resizable()
                        .scaledToFill()
                        .allowsHitTesting(false)

                    LinearGradient(
                        colors: [Color.black.opacity(0.02), Color.black.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .frame(height: 190)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.image, style: .continuous))

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.displayGardenName(garden.name))
                            .font(ArboreDesign.Typography.cardTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                            .lineLimit(2)

                        Text(L10n.f("PLANT_COUNT_FORMAT", garden.plants.count))
                            .font(ArboreDesign.Typography.caption)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)

                        if let d = garden.updatedAt {
                            Text(L10n.f("LAST_MODIFIED_FORMAT", d.formatted(date: .abbreviated, time: .omitted)))
                                .font(ArboreDesign.Typography.caption)
                                .foregroundColor(ArboreDesign.Colors.textMuted)
                        }
                    }

                    Spacer()

                    Text(L10n.t("COMMON_OPEN"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(ArboreDesign.Colors.primaryButton)
                        .clipShape(Capsule())
                }
            }
            .padding(ArboreDesign.Spacing.sm)
            .background(ArboreDesign.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                    .stroke(ArboreDesign.Colors.border, lineWidth: 1)
            )
            .shadow(color: ArboreDesign.Colors.shadow, radius: 10, x: 0, y: 4)
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
