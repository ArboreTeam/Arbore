import SwiftUI

struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PlantDetailView: View {
    let plantID: String
    let previewPlant: Plant?

    @State private var plant: Plant?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showFullDescription = false
    @State private var showGallery = false
    @State private var galleryStartIndex = 0
    @State private var scrollOffset: CGFloat = 0
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var themeManager: ThemeManager

    init(plantID: String, previewPlant: Plant? = nil) {
        self.plantID = plantID
        self.previewPlant = previewPlant
    }

    // MARK: - Langue effective (UI + traductions)
    private var effectiveLanguageCode: String {
        func normalize(_ raw: String) -> String {
            let lower = raw.lowercased()
            if let dash = lower.firstIndex(of: "-") {
                return String(lower[..<dash])
            }
            if let underscore = lower.firstIndex(of: "_") {
                return String(lower[..<underscore])
            }
            return lower
        }

        if selectedLanguage != "system" && !selectedLanguage.isEmpty {
            return normalize(selectedLanguage)
        }

        let appLang = Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"

        return normalize(appLang)
    }

    private func translation(for plant: Plant) -> PlantTranslation? {
        let lang = effectiveLanguageCode

        if let t = plant.translations[lang] {
            return t
        } else if let en = plant.translations["en"] {
            return en
        } else {
            return plant.translations.values.first
        }
    }

    private var displayPlant: Plant? {
        plant ?? previewPlant
    }

    private var displayedPlantType: String? {
        guard let plant = displayPlant else { return nil }

        let rawType: String
        if let t = translation(for: plant) {
            rawType = t.plantType
        } else {
            rawType = plant.type
        }

        let cleanType = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanType.isEmpty else { return nil }

        let lowered = cleanType.lowercased()
        if lowered.contains("unknown") || lowered.contains("inconnu") {
            return nil
        }
        return cleanType.capitalized
    }

    var body: some View {
        ZStack(alignment: .top) {
            ArboreDesign.Colors.background.ignoresSafeArea()

            if let errorMessage = errorMessage, displayPlant == nil {
                Text(errorMessage)
                    .font(ArboreDesign.Typography.body)
                    .foregroundColor(ArboreDesign.Colors.danger)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                plantContent(displayPlant, isShowingSkeleton: plant == nil)
            }

            topBar
        }
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: fetchPlantDetails)
        .fullScreenCover(isPresented: $showGallery) {
            galleryOverlay
        }
        .toolbar(showGallery ? .hidden : .visible, for: .tabBar)
    }

    // MARK: - TOP BAR

    private var topBar: some View {
        ZStack(alignment: .bottom) {
            Group {
                if scrollOffset < -5 {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                } else {
                    ArboreDesign.Colors.background
                }
            }
            .ignoresSafeArea(edges: .top)
            .frame(height: 64)
            .animation(.easeInOut(duration: 0.2), value: scrollOffset)

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(ArboreDesign.Colors.primaryGreen)
                        .font(.headline)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 2) {
                    if let name = displayPlant?.name, !name.isEmpty {
                        Text(name)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(ArboreDesign.Colors.textPrimary)
                            .lineLimit(1)
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ArboreDesign.Colors.textMuted.opacity(0.28))
                            .frame(width: 118, height: 17)
                    }

                    if let displayedPlantType {
                        Text(displayedPlantType)
                            .font(ArboreDesign.Typography.caption)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                            .lineLimit(1)
                    } else {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(ArboreDesign.Colors.textMuted.opacity(0.18))
                            .frame(width: 82, height: 10)
                    }
                }

                Spacer()

                Color.clear
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
    }

    // MARK: - CONTENT

    private func plantContent(_ displayPlant: Plant?, isShowingSkeleton: Bool) -> some View {
        let t = plant.flatMap { translation(for: $0) }

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self,
                                    value: geo.frame(in: .named("scroll")).minY)
                }
                .frame(height: 64)

                plantHeaderImage(for: displayPlant)

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(ArboreDesign.Colors.background)
                        .padding(.top, -32)

                    VStack(alignment: .leading, spacing: 24) {
                        if isShowingSkeleton {
                            descriptionSkeleton
                            essentialsSkeleton
                            guideSkeleton
                        } else if let plant = displayPlant {
                            descriptionSection(t: t, plant: plant)

                            essentialsSection(t: t)

                            GeneralInfoGridView(translation: t, plantName: plant.name)

                            gallerySection(for: plant)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                    .padding(.top, 5)
                }
            }
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            scrollOffset = value
        }
    }

    // MARK: - HEADER IMAGE

    private func plantHeaderImage(for displayPlant: Plant?) -> some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                let offset = geo.frame(in: .named("scroll")).minY

                if let imageURL = displayPlant?.imageURLs.first, !imageURL.isEmpty {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: UIScreen.main.bounds.width,
                                height: offset > 0 ? 320 + offset : 320
                            )
                            .clipped()
                            .offset(y: offset > 0 ? -offset : 0)
                    } placeholder: {
                        heroSkeleton
                    }
                } else {
                    heroSkeleton
                }
            }
            .frame(height: 320)
        }
        .frame(height: 320)
    }

    private var heroSkeleton: some View {
        SkeletonBlock(cornerRadius: 0)
            .frame(height: 320)
    }

    // MARK: - DESCRIPTION

    private func descriptionSection(t: PlantTranslation?, plant: Plant) -> some View {
        let descriptionText = t?.description ?? plant.description

        return HStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image("description_icon")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(ArboreDesign.Colors.primaryGreen)
                        .frame(width: 25, height: 25)

                    Text(NSLocalizedString("PLANTDETAIL_SECTION_DESCRIPTION", comment: ""))
                        .font(ArboreDesign.Typography.sectionTitle)
                        .foregroundColor(ArboreDesign.Colors.textPrimary)

                    Spacer()
                }

                Text(descriptionText)
                    .font(ArboreDesign.Typography.body)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(showFullDescription ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)

                if shouldShowReadMore(for: descriptionText) {
                    Button(action: {
                        withAnimation { showFullDescription.toggle() }
                    }) {
                        Text(
                            showFullDescription
                            ? NSLocalizedString("PLANTDETAIL_READ_LESS", comment: "")
                            : NSLocalizedString("PLANTDETAIL_READ_MORE", comment: "")
                        )
                        .font(ArboreDesign.Typography.bodySmall.weight(.semibold))
                        .foregroundColor(ArboreDesign.Colors.primaryGreen)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(ArboreDesign.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                    .stroke(ArboreDesign.Colors.border, lineWidth: 1)
            )
            .shadow(color: ArboreDesign.Colors.shadow, radius: 8, x: 0, y: 4)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private func shouldShowReadMore(for text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count > 110
    }

    // MARK: - ESSENTIALS

    private func essentialsSection(t: PlantTranslation?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                Text(NSLocalizedString("PLANTDETAIL_ESSENTIALS_TITLE", value: "Essentiels", comment: ""))
                    .font(ArboreDesign.Typography.sectionTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
            }
            .padding(.horizontal)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                EssentialPlantInfoCard(
                    icon: "sun.max.fill",
                    title: NSLocalizedString("PLANTDETAIL_SUN_TITLE", comment: ""),
                    value: firstAvailable(t?.sun?.lightType, t?.sun?.durationPerDay),
                    tint: ArboreDesign.Colors.accentGold
                )

                EssentialPlantInfoCard(
                    icon: "drop.fill",
                    title: NSLocalizedString("PLANTDETAIL_WATER_TITLE", comment: ""),
                    value: firstAvailable(t?.water?.frequency, t?.water?.amount),
                    tint: ArboreDesign.Colors.primaryGreen
                )

                EssentialPlantInfoCard(
                    icon: "hand.raised.fill",
                    title: NSLocalizedString("PLANTDETAIL_CARE_TITLE", comment: ""),
                    value: firstAvailable(t?.care?.difficulty),
                    tint: ArboreDesign.Colors.primaryGreen
                )

                EssentialPlantInfoCard(
                    icon: "arrow.up.right",
                    title: NSLocalizedString("PLANTDETAIL_GROWTH_TITLE", value: "Croissance", comment: ""),
                    value: firstAvailable(t?.lifeCycle?.growth, t?.soilAndPot?.repotFrequency),
                    tint: ArboreDesign.Colors.accentGold
                )
            }
            .padding(.horizontal)
        }
    }

    private func firstAvailable(_ values: String?...) -> String {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return NSLocalizedString("PLANTDETAIL_INFO_UNAVAILABLE", value: "Non renseigné", comment: "")
    }

    // MARK: - SKELETONS

    private var descriptionSkeleton: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SkeletonBlock(width: 25, height: 25, cornerRadius: 8)
                    SkeletonBlock(width: 132, height: 20, cornerRadius: 8)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(height: 14, cornerRadius: 7)
                    SkeletonBlock(height: 14, cornerRadius: 7)
                    SkeletonBlock(width: 210, height: 14, cornerRadius: 7)
                }
            }
            .padding(20)
            .background(ArboreDesign.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                    .stroke(ArboreDesign.Colors.border, lineWidth: 1)
            )
            .shadow(color: ArboreDesign.Colors.shadow, radius: 8, x: 0, y: 4)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var essentialsSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SkeletonBlock(width: 18, height: 18, cornerRadius: 7)
                SkeletonBlock(width: 96, height: 20, cornerRadius: 8)
            }
            .padding(.horizontal)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBlock(width: 30, height: 30, cornerRadius: 15)
                        SkeletonBlock(width: 70, height: 12, cornerRadius: 6)
                        SkeletonBlock(height: 14, cornerRadius: 7)
                        SkeletonBlock(width: 92, height: 14, cornerRadius: 7)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                    .background(ArboreDesign.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                            .stroke(ArboreDesign.Colors.border, lineWidth: 1)
                    )
                    .shadow(color: ArboreDesign.Colors.shadow, radius: 4, x: 0, y: 2)
                }
            }
            .padding(.horizontal)
        }
    }

    private var guideSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                SkeletonBlock(width: 18, height: 18, cornerRadius: 7)
                SkeletonBlock(width: 146, height: 20, cornerRadius: 8)
            }
            .padding(.horizontal)

            VStack(spacing: 14) {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(spacing: 12) {
                        SkeletonBlock(width: 38, height: 38, cornerRadius: 19)
                        VStack(alignment: .leading, spacing: 7) {
                            SkeletonBlock(width: 118, height: 16, cornerRadius: 8)
                            SkeletonBlock(width: 190, height: 12, cornerRadius: 6)
                        }
                        Spacer()
                        SkeletonBlock(width: 8, height: 14, cornerRadius: 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(ArboreDesign.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                            .stroke(ArboreDesign.Colors.border, lineWidth: 1)
                    )
                    .shadow(color: ArboreDesign.Colors.shadow, radius: 4, x: 0, y: 2)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - GALLERY

    private func gallerySection(for plant: Plant) -> some View {
        Group {
            if plant.imageURLs.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text(NSLocalizedString("PLANTDETAIL_GALLERY_TITLE", comment: ""))
                            .font(ArboreDesign.Typography.cardTitle)
                            .foregroundColor(ArboreDesign.Colors.textPrimary)

                        Spacer()

                        Button(action: {
                            galleryStartIndex = 0
                            showGallery = true
                        }) {
                            Text(NSLocalizedString("PLANTDETAIL_GALLERY_SEE_ALL", comment: ""))
                                .font(ArboreDesign.Typography.bodySmall.weight(.semibold))
                                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(plant.imageURLs.indices, id: \.self) { index in
                                AsyncImage(url: URL(string: plant.imageURLs[index])) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
                                } placeholder: {
                                    ArboreDesign.Colors.elevatedCard
                                        .frame(width: 120, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
                                        .overlay(
                                            ProgressView()
                                                .tint(ArboreDesign.Colors.primaryGreen)
                                        )
                                }
                                .onTapGesture {
                                    galleryStartIndex = index
                                    showGallery = true
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
                .background(ArboreDesign.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                        .stroke(ArboreDesign.Colors.border, lineWidth: 1)
                )
                .shadow(color: ArboreDesign.Colors.shadow, radius: 8, x: 0, y: 4)
            }
        }
        .padding(.bottom)
    }

    private var galleryOverlay: some View {
        Group {
            if showGallery, let plant = plant {
                PlantPhotoGallery(images: plant.imageURLs, isPresented: $showGallery)
            } else {
                Color.clear
            }
        }
    }

    // MARK: - NETWORKING

    private func fetchPlantDetails() {
        Task {
            do {
                let plant: Plant = try await NetworkManager.shared.request(
                    endpoint: "/plants/\(plantID)",
                    method: .GET
                )

                await MainActor.run {
                    self.plant = plant
                    self.errorMessage = nil
                    self.showFullDescription = false
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    let format = NSLocalizedString("PLANTDETAIL_ERROR_CONNECTION_FORMAT", comment: "")
                    self.errorMessage = String(format: format, error.localizedDescription)
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - SKELETON

struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat?
    var cornerRadius: CGFloat = ArboreDesign.Radius.medium
    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(ArboreDesign.Colors.softSurface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ArboreDesign.Colors.card.opacity(isPulsing ? 0.42 : 0.12))
            )
            .opacity(isPulsing ? 0.72 : 1)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - ESSENTIAL CARD

struct EssentialPlantInfoCard: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .clipShape(Circle())

            Text(title)
                .font(ArboreDesign.Typography.caption.weight(.semibold))
                .foregroundColor(ArboreDesign.Colors.textMuted)
                .lineLimit(1)

            Text(value)
                .font(ArboreDesign.Typography.bodySmall.weight(.semibold))
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
        .shadow(color: ArboreDesign.Colors.shadow, radius: 4, x: 0, y: 2)
    }
}

// MARK: - GENERAL INFO GRID (Soleil / Eau / Terre / Santé / Cycle / Entretien)

struct GeneralInfoGridView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    let translation: PlantTranslation?
    let plantName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.below.ecg.fill")
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                Text(NSLocalizedString("PLANTDETAIL_CARE_GUIDE_TITLE", value: "Guide d’entretien", comment: "Plant care guide title"))
                    .font(ArboreDesign.Typography.sectionTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
            }
            .padding(.horizontal)

            VStack(spacing: 14) {
                GeneralInfoCard(
                    icon: "sun.max.fill",
                    title: NSLocalizedString("PLANTDETAIL_SUN_TITLE", comment: ""),
                    description: NSLocalizedString("PLANTDETAIL_SUN_SUBTITLE", comment: ""),
                    color: ArboreDesign.Colors.accentGold,
                    destination: SoleilDetailView(sun: translation?.sun)
                )
                GeneralInfoCard(
                    icon: "drop.fill",
                    title: NSLocalizedString("PLANTDETAIL_WATER_TITLE", comment: ""),
                    description: NSLocalizedString("PLANTDETAIL_WATER_SUBTITLE", comment: ""),
                    color: ArboreDesign.Colors.primaryGreen,
                    destination: EauDetailView(water: translation?.water, plantName: plantName)
                )
                GeneralInfoCard(
                    icon: "leaf.fill",
                    title: NSLocalizedString("PLANTDETAIL_SOIL_TITLE", comment: ""),
                    description: NSLocalizedString("PLANTDETAIL_SOIL_SUBTITLE", comment: ""),
                    color: ArboreDesign.Colors.primaryGreen,
                    destination: TerreDetailView(soil: translation?.soilAndPot, plantName: plantName)
                )
                GeneralInfoCard(
                    icon: "cross.case.fill",
                    title: NSLocalizedString("PLANTDETAIL_HEALTH_TITLE", comment: ""),
                    description: NSLocalizedString("PLANTDETAIL_HEALTH_SUBTITLE", comment: ""),
                    color: ArboreDesign.Colors.danger,
                    destination: SanteDetailView(health: translation?.health)
                )
                GeneralInfoCard(
                    icon: "calendar",
                    title: NSLocalizedString("PLANTDETAIL_LIFECYCLE_TITLE", comment: ""),
                    description: NSLocalizedString("PLANTDETAIL_LIFECYCLE_SUBTITLE", comment: ""),
                    color: ArboreDesign.Colors.accentGold,
                    destination: CycleDeVieView(lifecycle: translation?.lifeCycle)
                )
                GeneralInfoCard(
                    icon: "brain.head.profile",
                    title: NSLocalizedString("PLANTDETAIL_CARE_TITLE", comment: ""),
                    description: NSLocalizedString("PLANTDETAIL_CARE_SUBTITLE", comment: ""),
                    color: ArboreDesign.Colors.primaryGreen,
                    destination: EntretienView(care: translation?.care)
                )
            }
            .padding(.horizontal)
        }
    }
}

struct GeneralInfoCard<Destination: View>: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let destination: Destination
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(colorScheme == .dark ? 0.18 : 0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 18, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(ArboreDesign.Typography.cardTitle)
                        .foregroundColor(ArboreDesign.Colors.textPrimary)
                    Text(description)
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                }

                Spacer()
                Image(systemName: ArboreDesign.Icons.chevron)
                    .foregroundColor(ArboreDesign.Colors.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(ArboreDesign.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                    .stroke(ArboreDesign.Colors.border, lineWidth: 1)
            )
            .shadow(color: ArboreDesign.Colors.shadow, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
