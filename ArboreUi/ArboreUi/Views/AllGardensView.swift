import SwiftUI

/// Écran "Voir tout" : affiche tous les jardins (même style que la Home),
/// et ouvre directement l’AR au tap sur une carte.
struct AllGardensView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    let currentGardenId: String?
    let onSelectGarden: ((GardenDTO) -> Void)?
    let onDismiss: (() -> Void)?
    let onGardenDeleted: ((String) -> Void)?

    @State private var gardens: [GardenDTO] = []
    @State private var gardenToOpen: GardenDTO? = nil
    @State private var gardenToDelete: GardenDTO? = nil
    @State private var deletingGardenId: String? = nil
    @State private var deleteErrorMessage: String? = nil

    // Style dynamique via themeManager
    private var background: Color { themeManager.backgroundColor }
    private var primary: Color { themeManager.accentColor }
    private var textDark: Color { themeManager.textColor }
    private var textSubtle: Color { themeManager.secondaryTextColor }
    private var cardLight: Color { themeManager.cardBackgroundColor }

    // Arrondis (aligné Home “moelleux”)
    private let cardCorner: CGFloat = 28
    private let imageCorner: CGFloat = 24

    init(
        currentGardenId: String? = nil,
        onSelectGarden: ((GardenDTO) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        onGardenDeleted: ((String) -> Void)? = nil
    ) {
        self.currentGardenId = currentGardenId
        self.onSelectGarden = onSelectGarden
        self.onDismiss = onDismiss
        self.onGardenDeleted = onGardenDeleted
    }

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
        .alert(L10n.t("ALL_GARDENS_DELETE_CONFIRM_TITLE"), isPresented: deleteConfirmationPresented) {
            Button(L10n.t("COMMON_CANCEL"), role: .cancel) {
                gardenToDelete = nil
            }
            Button(L10n.t("COMMON_DELETE"), role: .destructive) {
                if let gardenToDelete {
                    Task { await deleteGarden(gardenToDelete) }
                }
            }
        } message: {
            Text(L10n.t("ALL_GARDENS_DELETE_CONFIRM_MESSAGE"))
        }
        .alert(L10n.t("ALL_GARDENS_DELETE_ERROR_TITLE"), isPresented: deleteErrorPresented) {
            Button(L10n.t("COMMON_OK"), role: .cancel) {
                deleteErrorMessage = nil
            }
        } message: {
            Text(deleteErrorMessage ?? "")
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
    var isSelectionMode: Bool {
        onSelectGarden != nil
    }

    var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { gardenToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    gardenToDelete = nil
                }
            }
        )
    }

    var deleteErrorPresented: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deleteErrorMessage = nil
                }
            }
        )
    }

    func fetchGardens() async {
        do {
            let list = try await GardenAPI.shared.listGardens()
            await MainActor.run { self.gardens = list }
        } catch {
            // #391 — /gardens est fermé aux invités : liste vide, pas une panne.
            if error.isAccountRequired {
                await MainActor.run { self.gardens = [] }
                return
            }
            print("❌ fetchGardens failed:", error)
        }
    }

    func openGarden(_ garden: GardenDTO) {
        if let onSelectGarden {
            onSelectGarden(garden)
        } else {
            gardenToOpen = garden
        }
    }

    func deleteGarden(_ garden: GardenDTO) async {
        guard let id = garden.id else { return }

        await MainActor.run {
            deletingGardenId = id
            gardenToDelete = nil
        }

        do {
            try await GardenAPI.shared.deleteGarden(id: id)
            deleteLocalGardenFiles(id: id)

            await MainActor.run {
                gardens.removeAll { $0.id == id }
                deletingGardenId = nil
                onGardenDeleted?(id)
            }
        } catch {
            await MainActor.run {
                deletingGardenId = nil
                deleteErrorMessage = error.localizedDescription
            }
        }
    }

    func deleteLocalGardenFiles(id: String) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: GardenLocalStore.sceneURL(for: id))
        try? fileManager.removeItem(at: GardenLocalStore.worldMapURL(for: id))
        GardenLocalStore.removeWizard(for: id)
        LocalDataOwnership.forget(id)
    }
}

// MARK: - UI
private extension AllGardensView {

    /// Top bar alignée au style Home (typo serif + discret, bouton back “soft”)
    var topBar: some View {
        HStack(spacing: 12) {
            Button {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            } label: {
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
                Text(L10n.t("ALL_GARDENS_TITLE"))
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundColor(textDark)

                Text(isSelectionMode ? L10n.t("ALL_GARDENS_SELECTION_SUBTITLE") : L10n.f("ALL_GARDENS_TOTAL_FORMAT", gardens.count))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textSubtle.opacity(0.9))
            }

            Spacer()
        }
    }

    var emptyState: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("ALL_GARDENS_EMPTY_TITLE"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textDark)

                Text(L10n.t("ALL_GARDENS_EMPTY_SUBTITLE"))
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
        let isCurrent = garden.id == currentGardenId
        let isDeleting = deletingGardenId == garden.id

        return VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
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

                if isCurrent {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(L10n.t("ALL_GARDENS_CURRENT"))
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(primary)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 4)
                    .padding(12)
                }
            }
            // ✅ IMPORTANT : même logique que Home → hauteur fixe
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: imageCorner, style: .continuous))
            .padding(.top, 12)
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.displayGardenName(garden.name))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(textDark)

                        Text(L10n.f("PLANT_COUNT_FORMAT", garden.plants.count))
                            .font(.system(size: 13))
                            .foregroundColor(textSubtle)

                        if let d = garden.updatedAt {
                            Text(L10n.f("LAST_MODIFIED_FORMAT", d.formatted(date: .abbreviated, time: .omitted)))
                                .font(.system(size: 12))
                                .foregroundColor(textSubtle.opacity(0.9))
                        }
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    Button {
                        gardenToDelete = garden
                    } label: {
                        if isDeleting {
                            ProgressView()
                                .tint(textSubtle)
                                .frame(width: 40, height: 36)
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(ArboreDesign.Colors.danger)
                                .frame(width: 40, height: 36)
                        }
                    }
                    .buttonStyle(.plain)
                    .background(ArboreDesign.Colors.danger.opacity(0.10))
                    .clipShape(Capsule())
                    .disabled(isDeleting)
                    .accessibilityLabel(L10n.f("ALL_GARDENS_DELETE_ACCESSIBILITY_FORMAT", garden.name))

                    Button {
                        openGarden(garden)
                    } label: {
                        Text(isSelectionMode ? (isCurrent ? L10n.t("COMMON_SELECTED") : L10n.t("COMMON_CHOOSE")) : L10n.t("COMMON_OPEN"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(isCurrent && isSelectionMode ? textSubtle : primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(cardLight)
        .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .stroke(isCurrent ? primary.opacity(0.7) : ArboreDesign.Colors.border, lineWidth: isCurrent ? 2 : 1)
        )
        .shadow(color: isCurrent ? primary.opacity(0.16) : .black.opacity(0.06), radius: 12, x: 0, y: 6)
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
