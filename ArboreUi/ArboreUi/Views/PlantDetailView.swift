import SwiftUI
import ARKit
import RealityKit

struct PlantDetailView: View {
    let plantID: String
    @State private var plant: Plant?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isLiked: Bool = false
    @State private var showARView = false
    @State private var currentPage = 0
    @State private var showFullDescription = false
    @State private var showGallery = false
    @State private var galleryStartIndex = 0
    @State private var isAddedToGarden = false
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Langue effective (UI + traductions)
    private var effectiveLanguageCode: String {
        // normalisation d’un code ("es-ES" -> "es")
        func normalize(_ raw: String) -> String {
            let lower = raw.lowercased()
            if let dash = lower.firstIndex(of: "-") {
                return String(lower[..<dash])
            }
            if let underscore = lower.firstIndex(of: "_") {
                return String(lower[..<underscore])
            }
            return lower      // déjà "fr", "en", "es", …
        }

        // 1) si l’utilisateur a choisi une langue explicite
        if selectedLanguage != "system" && !selectedLanguage.isEmpty {
            return normalize(selectedLanguage)
        }

        // 2) sinon on suit la langue de l’app
        let appLang = Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"

        return normalize(appLang)   // "es", "fr", "en", …
    }

    private func translation(for plant: Plant) -> PlantTranslation? {
        let lang = effectiveLanguageCode   // ex: "es"

        if let t = plant.translations[lang] {
            return t                // prend "es" si dispo
        } else if let en = plant.translations["en"] {
            return en               // fallback anglais
        } else {
            return plant.translations.values.first
        }
    }

    private var localizedPlantType: String {
        guard let plant = plant else {
            return NSLocalizedString("PLANTDETAIL_TYPE_UNKNOWN", comment: "")
        }
        if let t = translation(for: plant) {
            return t.plantType
        }
        if !plant.type.isEmpty {
            return plant.type
        }
        return NSLocalizedString("PLANTDETAIL_TYPE_UNKNOWN", comment: "")
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if isLoading {
                ProgressView(NSLocalizedString("PLANTDETAIL_LOADING", comment: "Loading plant"))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding()
            } else if let errorMessage = errorMessage {
                Text("❌ \(errorMessage)")
                    .foregroundColor(.red)
                    .padding()
            } else if let plant = plant {
                let t = translation(for: plant)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        plantHeaderImage

                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 32)
                                .fill(colorScheme == .dark ? Color(hex: "#1A1A1A") : Color(hex: "#F1F5ED"))
                                .padding(.top, -32)
                                .padding(.bottom, -200)

                            VStack(alignment: .leading, spacing: 24) {
                                addToGardenButton

                                descriptionSection(t: t, plant: plant)

                                // Cartes Soleil / Eau / Terre / Santé / Cycle / Entretien
                                GeneralInfoGridView(translation: t, plantName: plant.name)

                                arSection(for: plant)

                                gallerySection(for: plant)

                                truffautSection(for: plant)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 40)
                            .padding(.top, 5)
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: fetchPlantDetails)
        .overlay(galleryOverlay)
    }

    // MARK: - TOP BAR

    private var topBar: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "#263826")
                .ignoresSafeArea(edges: .top)
                .frame(height: 75)

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .font(.headline)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text(plant?.name ?? "")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(localizedPlantType.capitalized)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Button(action: { isLiked.toggle() }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundColor(isLiked ? .red : .white)
                        .font(.title2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    // MARK: - HEADER IMAGE

    private var plantHeaderImage: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                let offset = geo.frame(in: .named("scroll")).minY

                AsyncImage(url: URL(string: plant?.imageURLs.first ?? "")) { image in
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
                    Color.gray.opacity(0.2)
                        .frame(height: 320)
                        .overlay(ProgressView())
                }
            }
            .frame(height: 320)
        }
        .frame(height: 320)
    }

    // MARK: - ADD TO GARDEN BUTTON

    private var addToGardenButton: some View {
        HStack {
            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isAddedToGarden = true
                }
            }) {
                Text(
                    isAddedToGarden
                    ? NSLocalizedString("PLANTDETAIL_ADDED_TO_GARDEN", comment: "")
                    : NSLocalizedString("PLANTDETAIL_ADD_TO_GARDEN", comment: "")
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isAddedToGarden ? Color(hex: "#B5D3B2") : Color(hex: "#263826"))
                .foregroundColor(isAddedToGarden ? Color(hex: "#263826") : .white)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }

            Spacer()
        }
        .offset(y: -50)
        .padding(.bottom, -80)
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
                        .foregroundColor(Color(hex: "#263826"))
                        .frame(width: 25, height: 25)

                    Text(NSLocalizedString("PLANTDETAIL_SECTION_DESCRIPTION", comment: ""))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "#2C2F24"))

                    Spacer()
                }

                Text(descriptionText)
                    .font(.system(size: 15))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : Color(hex: "#2C2F24"))
                    .lineLimit(showFullDescription ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if descriptionText.count > 100 {
                    Button(action: {
                        withAnimation { showFullDescription.toggle() }
                    }) {
                        Text(
                            showFullDescription
                            ? NSLocalizedString("PLANTDETAIL_READ_LESS", comment: "")
                            : NSLocalizedString("PLANTDETAIL_READ_MORE", comment: "")
                        )
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(hex: "#263826"))
                    }
                }
            }
            .padding(20)
            .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color(hex: "#D9E0D2"))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 8, x: 0, y: 4)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - AR VIEW SECTION

    private func arSection(for plant: Plant) -> some View {
        VStack(spacing: 12) {
            Text(NSLocalizedString("PLANTDETAIL_AR_TITLE", comment: ""))
                .font(.headline)
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "#263826"))

            Text(NSLocalizedString("PLANTDETAIL_AR_SUBTITLE", comment: ""))
                .font(.subheadline)
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Image("plant_scanner_placeholder")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 180)

            Button(action: { showARView = true }) {
                Text(NSLocalizedString("PLANTDETAIL_AR_CTA", comment: ""))
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "#263826"))
                    .cornerRadius(12)
            }
            .fullScreenCover(isPresented: $showARView) {
                if let modelURL = plant.localModelURL {
                    ARViewWrapper(modelURL: modelURL)
                } else if let demoURL = getDemoModelURL() {
                    ARViewWrapper(modelURL: demoURL)
                } else {
                    ARViewBasic()
                }
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
        .cornerRadius(20)
    }

    // MARK: - GALLERY

    private func gallerySection(for plant: Plant) -> some View {
        Group {
            if plant.imageURLs.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#263826").opacity(0.1))
                                .frame(width: 32, height: 32)
                            Image(systemName: "photo.on.rectangle")
                                .foregroundColor(Color(hex: "#263826"))
                        }

                        Text(NSLocalizedString("PLANTDETAIL_GALLERY_TITLE", comment: ""))
                            .font(.headline)
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "#263826"))

                        Spacer()

                        Button(action: {
                            galleryStartIndex = 0
                            showGallery = true
                        }) {
                            Text(NSLocalizedString("PLANTDETAIL_GALLERY_SEE_ALL", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
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
                                        .cornerRadius(16)
                                } placeholder: {
                                    Color.gray.opacity(0.2)
                                        .frame(width: 120, height: 120)
                                        .cornerRadius(16)
                                        .overlay(ProgressView())
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
                .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                .cornerRadius(20)
            }
        }
        .padding(.bottom)
    }

    private var galleryOverlay: some View {
        Group {
            if showGallery, let plant = plant {
                PlantPhotoGallery(images: plant.imageURLs, isPresented: $showGallery)
            }
        }
    }

    // MARK: - TRUFFAUT CTA

    private func truffautSection(for plant: Plant) -> some View {
        ZStack {
            Image("truffaut_banner_frame")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 360)

            Button(action: {
                if let url = URL(
                    string: "https://www.truffaut.com/recherche?q=\(plant.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                ) {
                    UIApplication.shared.open(url)
                }
            }) {
                Image("truffaut_cta")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 300)
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.08), radius: 10)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    // MARK: - NETWORKING

    private func fetchPlantDetails() {
        guard let url = URL(string: "\(AppConfig.plantsEndpoint)/\(plantID)") else {
            self.errorMessage = NSLocalizedString("PLANTDETAIL_ERROR_URL_INVALID", comment: "")
            self.isLoading = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error = error {
                    let format = NSLocalizedString("PLANTDETAIL_ERROR_CONNECTION_FORMAT", comment: "")
                    errorMessage = String(format: format, error.localizedDescription)
                    return
                }

                guard let data = data else {
                    errorMessage = NSLocalizedString("PLANTDETAIL_ERROR_INVALID_DATA", comment: "")
                    return
                }

                do {
                    plant = try JSONDecoder().decode(Plant.self, from: data)
                } catch {
                    let format = NSLocalizedString("PLANTDETAIL_ERROR_DECODING_FORMAT", comment: "")
                    errorMessage = String(format: format, "\(error)")
                    print("❌ Décodage PlantDetailView :", error)
                }
            }
        }
        .resume()
    }

    // MARK: - AR FALLBACK

    private func getDemoModelURL() -> URL? {
        if let url = Bundle.main.url(forResource: "plant2", withExtension: "usdz", subdirectory: "Assets") {
            return url
        }
        if let url = Bundle.main.url(forResource: "plant2", withExtension: "usdz") {
            return url
        }
        return nil
    }
}

// MARK: - GENERAL INFO GRID (Soleil / Eau / Terre / Santé / Cycle / Entretien)

struct GeneralInfoGridView: View {
    @Environment(\.colorScheme) private var colorScheme
    let translation: PlantTranslation?   // traduction MongoDB
    let plantName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.below.ecg.fill")
                    .foregroundColor(Color(hex: "#263826"))
                Text(NSLocalizedString("PLANTDETAIL_GENERALINFO_TITLE", comment: ""))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            .padding(.horizontal)

            VStack(spacing: 14) {
                GeneralInfoCard(
                    icon: "sun.max.fill",
                    title: NSLocalizedString("PLANTDETAIL_SUN_TITLE", comment: ""),
                    description: NSLocalizedString("PLANTDETAIL_SUN_SUBTITLE", comment: ""),
                    color: Color(hex: "#EEDB8B"),
                    destination: SoleilDetailView(sun: translation?.sun)
                )
                GeneralInfoCard(
                    icon: "drop.fill",
                    title: NSLocalizedString("PLANTDETAIL_WATER_TITLE", comment: ""),
                    description: NSLocalizedString("PLANTDETAIL_WATER_SUBTITLE", comment: ""),
                    color: Color(hex: "#A4C3D7"),
                    destination: EauDetailView(water: translation?.water, plantName: plantName)
                )
                GeneralInfoCard(
                    icon: "leaf.fill",
                    title: NSLocalizedString("PLANTDETAIL_SOIL_TITLE", comment: ""),
                    description: NSLocalizedString("PLANTDETAIL_SOIL_SUBTITLE", comment: ""),
                    color: Color(hex: "#A7C6AD"),
                    destination: TerreDetailView(soil: translation?.soilAndPot, plantName: plantName)
                )
                GeneralInfoCard(
                    icon: "cross.case.fill",
                    title: NSLocalizedString("PLANTDETAIL_HEALTH_TITLE", comment: ""),
                    description: NSLocalizedString("PLANTDETAIL_HEALTH_SUBTITLE", comment: ""),
                    color: Color(hex: "#E6A6A1"),
                    destination: SanteDetailView(health: translation?.health)
                )
                GeneralInfoCard(
                    icon: "calendar",
                    title: NSLocalizedString("PLANTDETAIL_LIFECYCLE_TITLE", comment: ""),
                    description: NSLocalizedString("PLANTDETAIL_LIFECYCLE_SUBTITLE", comment: ""),
                    color: Color(hex: "#EFCFAF"),
                    destination: CycleDeVieView(lifecycle: translation?.lifeCycle)
                )
                GeneralInfoCard(
                    icon: "brain.head.profile",
                    title: NSLocalizedString("PLANTDETAIL_CARE_TITLE", comment: ""),
                    description: NSLocalizedString("PLANTDETAIL_CARE_SUBTITLE", comment: ""),
                    color: Color(hex: "#C5B3E6"),
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

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 20, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .gray)
            }
            .padding()
            .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.04), radius: 4, x: 0, y: 2)
        }
    }
}

