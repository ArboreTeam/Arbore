import SwiftUI
import simd
import ARKit

struct PlantCatalogARView: View {
    let wizardFilter: GardenWizardDTO?
    let onSelect: (Plant) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var plants: [Plant] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var selectedChip: String = "Top Picks"

    private var plantFilter: WizardPlantFilter? {
        guard let wiz = wizardFilter else { return nil }
        return WizardPlantFilter(wizard: wiz)
    }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var types: [String] {
        let base = Set(
            plants
                .map { $0.type.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return base.sorted()
    }

    private var chips: [String] {
        if let pf = plantFilter, pf.hasActiveFilters {
            return ["Pour toi 🌱", "Top Picks"] + types
        }
        return ["Top Picks"] + types
    }

    private var filteredPlants: [Plant] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = plants

        // Apply wizard filter when "Pour toi" chip is selected
        if selectedChip == "Pour toi 🌱", let pf = plantFilter {
            list = list.filter { pf.matches(plant: $0, locale: "fr") }
        } else if selectedChip != "Top Picks" && selectedChip != "Pour toi 🌱" {
            list = list.filter { $0.type == selectedChip }
        }

        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) || $0.type.lowercased().contains(q) }
        }

        if (selectedChip == "Top Picks" || selectedChip == "Pour toi 🌱") && q.isEmpty {
            list = list.sorted {
                let a = ($0.modelURL?.isEmpty == false) ? 0 : 1
                let b = ($1.modelURL?.isEmpty == false) ? 0 : 1
                if a != b { return a < b }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.ignoresSafeArea()
                sheetFullscreen
            }
            .navigationBarHidden(true)
            .onAppear {
                // Set default chip to "Pour toi" if wizard filters are active
                if let pf = plantFilter, pf.hasActiveFilters {
                    selectedChip = "Pour toi 🌱"
                }
                fetchPlants()
            }
        }
    }

    private var sheetFullscreen: some View {
        GeometryReader { geo in
            let height = geo.size.height

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        ARCatColor.tint.opacity(0.08)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 26, x: 0, y: 8)

                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 48, height: 6)
                        .padding(.top, 10)
                        .padding(.bottom, 10)

                    HStack {
                        Text("Select a Plant")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)

                        Spacer()

                        Button { dismiss() } label: {
                            Text("Fermer")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .background(Color.black.opacity(0.18))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    chipsRow
                        .padding(.bottom, 6)

                    // Wizard filter banner
                    if selectedChip == "Pour toi 🌱" {
                        wizardFilterBanner
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }

                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: height)
                .frame(maxWidth: .infinity)
            }
            .frame(width: geo.size.width, height: height)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.55))

            TextField("Search for monstera, palm…", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .foregroundColor(.white)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.45))
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: ARCatColor.primary.opacity(0.14), radius: 18, x: 0, y: 8)
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(chips, id: \.self) { chip in
                    ChipView(
                        title: chip,
                        systemIcon: iconForChip(chip),
                        isActive: selectedChip == chip
                    ) {
                        selectedChip = chip
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    private var content: some View {
        Group {
            if isLoading {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView().tint(.white)
                    Text("Chargement…")
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
            } else if let errorMessage {
                VStack(spacing: 10) {
                    Spacer()
                    Text("❌ \(errorMessage)")
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Spacer()
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredPlants) { plant in
                            ZStack(alignment: .topTrailing) {
                                PlantCard(plant: plant)
                                    .contentShape(RoundedRectangle(cornerRadius: 16))
                                    .onTapGesture {
                                        onSelect(plant)
                                        dismiss()
                                    }

                                NavigationLink(destination: PlantDetailView(plantID: plant.id)) {
                                    ZStack {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .overlay(Circle().fill(Color.black.opacity(0.18)))
                                            .frame(width: 34, height: 34)
                                            .overlay(
                                                Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                                            )

                                        Image(systemName: "info")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white.opacity(0.92))
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(10)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    // MARK: - Wizard filter banner

    private var wizardFilterBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(ARCatColor.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sélection personnalisée")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)

                Text(wizardFilterSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(2)
            }

            Spacer()

            Text("\(filteredPlants.count)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(ARCatColor.primary)
                + Text(" plantes")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(ARCatColor.primary.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var wizardFilterSummary: String {
        guard let wiz = wizardFilter else { return "" }
        var parts: [String] = []
        if !wiz.style.isEmpty && !wiz.style.lowercased().contains("sans préférence") {
            parts.append("Style \(wiz.style.components(separatedBy: " &").first ?? wiz.style)")
        }
        if let e = wiz.exposure, !e.isEmpty {
            // Shorten the exposure text
            let short = e.replacingOccurrences(of: " (6h+)", with: "")
            parts.append(short)
        }
        if let m = wiz.maintenance, !m.isEmpty {
            parts.append("Entretien \(m.lowercased())")
        }
        if let safety = wiz.safety, !safety.isEmpty,
           !safety.contains("Aucune contrainte") {
            parts.append("Sécurité activée")
        }
        if let s = wiz.soil, !s.isEmpty,
           !s.lowercased().contains("je ne sais pas") {
            parts.append("Sol \(s.lowercased())")
        }
        return parts.isEmpty ? "Basé sur vos préférences" : parts.joined(separator: " · ")
    }

    private func iconForChip(_ chip: String) -> String {
        if chip == "Pour toi \u{1F331}" { return "sparkles" }
        if chip == "Top Picks" { return "star.fill" }
        let t = chip.lowercased()
        if t.contains("indoor") || t.contains("int") { return "house" }
        if t.contains("succ") || t.contains("cactus") { return "camera.macro" }
        if t.contains("tree") || t.contains("arbre") { return "leaf" }
        return "leaf"
    }

    private func fetchPlants() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let plants: [Plant] = try await NetworkManager.shared.request(
                    endpoint: "/plants",
                    method: .GET
                )

                await MainActor.run {
                    self.plants = plants
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Erreur: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Chip

fileprivate struct ChipView: View {
    let title: String
    let systemIcon: String
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: systemIcon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: isActive ? .bold : .semibold))
            }
            .foregroundColor(isActive ? ARCatColor.backgroundDark : .white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(isActive ? ARCatColor.primary : Color.white.opacity(0.06))
            .overlay(
                Capsule().stroke(Color.white.opacity(isActive ? 0.0 : 0.06), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card FIX (plus de “bande verte”)

fileprivate struct PlantCardGlass: View {
    let plant: Plant
    let onTap: () -> Void

    private var hasModel: Bool { (plant.modelURL?.isEmpty == false) }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                ZStack {
                    AsyncThumb(plant: plant)
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ARCatColor.surfaceDark)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )

                VStack {
                    HStack {
                        Spacer()
                        if hasModel {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Color.black.opacity(0.10))
                                Image(systemName: "arkit")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(ARCatColor.primary)
                            }
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                            .padding(10)
                        }
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Spacer()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(plant.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 2)

                        Text(plant.type)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.80))
                            .italic()
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)

                        HStack {
                            Text(hasModel ? "AR Ready" : "2D Preview")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(hasModel ? ARCatColor.primary : .white.opacity(0.75))
                                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)

                            Spacer()

                            ZStack {
                                Circle().fill(ARCatColor.primary)
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(ARCatColor.backgroundDark)
                            }
                            .frame(width: 32, height: 32)
                        }
                        .padding(.top, 4)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(Color.black.opacity(0.10))
                    )
                }
                .padding(10)
            }
            .aspectRatio(4/5, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Async thumb

fileprivate struct AsyncThumb: View {
    let plant: Plant

    @State private var fetchedImage: UIImage?
    @State private var didFailLoading = false

    var body: some View {
        Group {
            if let cached = PlantThumbnailCache.load(for: plant.id) {
                Image(uiImage: cached)
                    .resizable()
            } else if let fetchedImage {
                Image(uiImage: fetchedImage)
                    .resizable()
            } else if plant.imageURLs.first != nil, !didFailLoading {
                ZStack {
                    Color.white.opacity(0.06)
                    ProgressView().tint(.white.opacity(0.7))
                }
            } else {
                ZStack {
                    Color.white.opacity(0.06)
                    Image(systemName: "leaf")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .task(id: taskKey) {
            await loadRemoteThumbnailIfNeeded()
        }
    }

    private var taskKey: String {
        "\(plant.id)|\(plant.imageURLs.first ?? "")"
    }

    private func loadRemoteThumbnailIfNeeded() async {
        await MainActor.run {
            didFailLoading = false
        }

        guard fetchedImage == nil else { return }

        if PlantThumbnailCache.load(for: plant.id) != nil {
            return
        }

        guard let urlString = plant.imageURLs.first,
              let url = URL(string: urlString) else { return }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    didFailLoading = true
                }
                return
            }

            if PlantThumbnailCache.isLegacyThumbnail(image) {
                await MainActor.run {
                    didFailLoading = true
                }
                return
            }

            let cachedImage = await Task.detached(priority: .utility) {
                PlantThumbnailCache.save(image, plantID: plant.id)
            }.value

            await MainActor.run {
                fetchedImage = cachedImage
                didFailLoading = false
            }
        } catch {
            await MainActor.run {
                didFailLoading = true
            }
        }
    }
}

// MARK: - Colors

fileprivate enum ARCatColor {
    static let primary = Color(hex: "#2BEE79")
    static let backgroundDark = Color(hex: "#102217")
    static let surfaceDark = Color(hex: "#162B1E")
    static let tint = Color(hex: "#102217")
}

// MARK: - Notifications

extension Notification.Name {
    static let gardenARSave = Notification.Name("gardenARSave")
    static let gardenARLoad = Notification.Name("gardenARLoad")
}

// MARK: - Matrix <-> [Float]


// MARK: - Files

func documentsURL(_ fileName: String) -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(fileName)
}

let worldMapFileURL = documentsURL("garden_worldmap.arexperience")
let sceneFileURL    = documentsURL("garden_scene.json")

// MARK: - Bundle model lookup (same logic as Plant.localModelURL)

func resourceURLFromModelURLString(_ modelURL: String) -> URL? {
    let file = modelURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !file.isEmpty else { return nil }

    let ext  = (file as NSString).pathExtension
    let name = (file as NSString).deletingPathExtension
    let finalExt = ext.isEmpty ? "usdz" : ext

    let url = Bundle.main.url(forResource: name, withExtension: finalExt)
    if url == nil {
        print("❌ USDZ introuvable dans le bundle: \(name).\(finalExt)")
    }
    return url
}
