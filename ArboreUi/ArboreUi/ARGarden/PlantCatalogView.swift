import SwiftUI

struct PlantCatalogARView: View {
    let placementMode: ARPlacementMode
    let onSelect: (Plant) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var searchText = ""
    @State private var plants: [Plant] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var detailPlant: Plant?

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var resultsTitle: String {
        let count = filteredPlants.count
        let key = count == 1 ? "CATALOG_RESULTS_SINGLE" : "CATALOG_RESULTS_PLURAL"
        return String(format: NSLocalizedString(key, comment: "Catalog result count"), count)
    }

    private var compatiblePlants: [Plant] {
        plants.filter { PlantPlacementCompatibility.supports($0, mode: placementMode) }
    }

    private var filteredPlants: [Plant] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = compatiblePlants

        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q)
                    || $0.type.lowercased().contains(q)
            }
        }

        return list.sorted { lhs, rhs in
            let lhsHasModel = lhs.modelURL?.isEmpty == false
            let rhsHasModel = rhs.modelURL?.isEmpty == false
            if lhsHasModel != rhsHasModel { return lhsHasModel }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            catalogPage
                .navigationBarHidden(true)
                .sheet(item: $detailPlant) { plant in
                    PlantDetailView(plantID: plant.id, previewPlant: plant)
                }
                .onAppear {
                    fetchPlants()
                }
        }
    }

    private var catalogPage: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                catalogHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 12)

                searchBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                HStack {
                    modeBadge
                    Spacer(minLength: 10)
                    Text(resultsTitle)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var catalogHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("AR_PLANT_CATALOG_TITLE"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(themeManager.textColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                    .frame(width: 42, height: 42)
                    .background(themeManager.cardBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                            .stroke(themeManager.separatorColor.opacity(0.85), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
        }
    }

    private var modeBadge: some View {
        Label(L10n.f("AR_PLANT_CATALOG_MODE_BADGE_FORMAT", placementMode.label), systemImage: placementMode.icon)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(themeManager.brandPrimary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(themeManager.brandPrimary.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                    .stroke(themeManager.brandPrimary.opacity(0.22), lineWidth: 1)
            )
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(themeManager.secondaryTextColor)

            TextField(L10n.t("AR_PLANT_CATALOG_SEARCH_PLACEHOLDER"), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .foregroundColor(themeManager.textColor)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(themeManager.cardBackgroundColor)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }

    private var content: some View {
        Group {
            if isLoading {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView().tint(themeManager.brandPrimary)
                    Text(L10n.t("COMMON_LOADING"))
                        .foregroundColor(themeManager.secondaryTextColor)
                    Spacer()
                }
            } else if let errorMessage {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(themeManager.secondaryTextColor)
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(themeManager.secondaryTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button(L10n.t("COMMON_RETRY")) { fetchPlants() }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        .background(themeManager.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous))
                    Spacer()
                }
            } else {
                ScrollView(showsIndicators: false) {
                    if filteredPlants.isEmpty {
                        VStack(spacing: 10) {
                            Spacer(minLength: 60)
                            Image(systemName: placementMode.icon)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(themeManager.secondaryTextColor)
                            Text(L10n.t("AR_PLANT_CATALOG_NO_COMPATIBLE_PLANTS"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredPlants) { plant in
                                Button {
                                    onSelect(plant)
                                    dismiss()
                                } label: {
                                    PlantCard(plant: plant)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        onSelect(plant)
                                        dismiss()
                                    } label: {
                                        Label(L10n.t("AR_PLANT_CATALOG_PLACE"), systemImage: "plus")
                                    }

                                    Button {
                                        detailPlant = plant
                                    } label: {
                                        Label(L10n.t("AR_PLANT_CATALOG_VIEW_DETAILS"), systemImage: "info.circle")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
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
