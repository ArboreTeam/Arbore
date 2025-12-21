import SwiftUI
import simd
import ARKit

struct PlantCatalogARView: View {
    let onSelect: (Plant) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var plants: [Plant] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var selectedChip: String = "Top Picks"

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

    private var chips: [String] { ["Top Picks"] + types }

    private var filteredPlants: [Plant] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = plants

        if selectedChip != "Top Picks" {
            list = list.filter { $0.type == selectedChip }
        }

        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) || $0.type.lowercased().contains(q) }
        }

        if selectedChip == "Top Picks" && q.isEmpty {
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
            .onAppear(perform: fetchPlants)
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

    private func iconForChip(_ chip: String) -> String {
        if chip == "Top Picks" { return "star.fill" }
        let t = chip.lowercased()
        if t.contains("indoor") || t.contains("int") { return "house" }
        if t.contains("succ") || t.contains("cactus") { return "camera.macro" }
        if t.contains("tree") || t.contains("arbre") { return "leaf" }
        return "leaf"
    }

    private func fetchPlants() {
        guard let url = URL(string: "http://79.137.92.154:8080/plants") else {
            self.errorMessage = "URL invalide"
            self.isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                self.isLoading = false

                if let error {
                    self.errorMessage = "Erreur réseau: \(error.localizedDescription)"
                    return
                }
                guard let data else {
                    self.errorMessage = "Données invalides"
                    return
                }
                do {
                    self.plants = try JSONDecoder().decode([Plant].self, from: data)
                } catch {
                    self.errorMessage = "Erreur décodage JSON"
                }
            }
        }.resume()
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
                    AsyncThumb(urlString: plant.imageURLs.first)
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
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color.white.opacity(0.06)
                            ProgressView().tint(.white.opacity(0.7))
                        }
                    case .success(let image):
                        image.resizable()
                    case .failure:
                        ZStack {
                            Color.white.opacity(0.06)
                            Image(systemName: "leaf")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    @unknown default:
                        Color.white.opacity(0.06)
                    }
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

// MARK: - Persisted data

struct PersistedPlant: Codable {
    let plantID: String
    let plantName: String
    let modelURLString: String
    let transform: [Float] // 16 floats (column-major)
}

struct PersistedARScene: Codable {
    let savedAt: Date
    let plants: [PersistedPlant]
}

// MARK: - Matrix <-> [Float]

func matrixToFloatArray(_ m: simd_float4x4) -> [Float] {
    let c0 = m.columns.0
    let c1 = m.columns.1
    let c2 = m.columns.2
    let c3 = m.columns.3
    return [
        c0.x, c0.y, c0.z, c0.w,
        c1.x, c1.y, c1.z, c1.w,
        c2.x, c2.y, c2.z, c2.w,
        c3.x, c3.y, c3.z, c3.w
    ]
}

func floatArrayToMatrix(_ a: [Float]) -> simd_float4x4? {
    guard a.count == 16 else { return nil }
    return simd_float4x4(
        SIMD4<Float>(a[0], a[1], a[2], a[3]),
        SIMD4<Float>(a[4], a[5], a[6], a[7]),
        SIMD4<Float>(a[8], a[9], a[10], a[11]),
        SIMD4<Float>(a[12], a[13], a[14], a[15])
    )
}

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
