import SwiftUI

struct GardenSpaceProfileCard: View {
    let wizard: GardenWizardDTO
    let area: Float
    let perimeter: Float
    let onEdit: () -> Void
    let onRemeasure: () -> Void

    private var profile: GardenSiteProfileDTO {
        GardenSiteProfileResolver.resolvedProfile(for: wizard)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
            HStack(alignment: .top, spacing: ArboreDesign.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("GARDEN_PROFILE_TITLE"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(ArboreDesign.Colors.textPrimary)

                    Text(L10n.t("GARDEN_PROFILE_DESCRIPTION"))
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(ArboreDesign.Colors.primaryButton)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("GARDEN_PROFILE_EDIT"))
            }

            VStack(spacing: 0) {
                GardenProfileRow(
                    icon: "square.grid.2x2",
                    title: L10n.t("GARDEN_PROFILE_SPACE"),
                    value: GardenSiteProfileResolver.spaceTitle(wizard.spaceType),
                    metadata: wizard.spaceType.isEmpty ? nil : .declaredHigh
                )

                Divider().overlay(ArboreDesign.Colors.border)

                GardenProfileRow(
                    icon: "square.dashed",
                    title: L10n.t("GARDEN_STAT_SURFACE"),
                    value: area > 0 ? String(format: "%.2f m²", area) : nil,
                    metadata: area > 0 ? .measuredHigh : nil,
                    action: onRemeasure
                )

                Divider().overlay(ArboreDesign.Colors.border)

                GardenProfileRow(
                    icon: "arrow.triangle.turn.up.right.diamond",
                    title: L10n.t("GARDEN_STAT_PERIMETER"),
                    value: perimeter > 0 ? String(format: "%.2f m", perimeter) : nil,
                    metadata: perimeter > 0 ? .measuredHigh : nil,
                    action: onRemeasure
                )

                Divider().overlay(ArboreDesign.Colors.border)

                GardenProfileRow(
                    icon: "location.north.line.fill",
                    title: L10n.t("GARDEN_PROFILE_ORIENTATION"),
                    value: profile.orientation.map { GardenSiteProfileResolver.orientationText($0.degrees) },
                    metadata: profile.orientation?.metadata,
                    action: onEdit
                )

                Divider().overlay(ArboreDesign.Colors.border)

                GardenProfileRow(
                    icon: "sun.max.fill",
                    title: L10n.t("GARDEN_PROFILE_SUNLIGHT"),
                    value: profile.sunlight.map(GardenSiteProfileResolver.sunlightText),
                    metadata: profile.sunlight?.metadata,
                    action: onEdit
                )

                Divider().overlay(ArboreDesign.Colors.border)

                GardenProfileRow(
                    icon: "mountain.2",
                    title: L10n.t("GARDEN_PROFILE_SOIL"),
                    value: wizard.soil.flatMap { SoilType(rawValue: $0)?.title ?? $0 },
                    metadata: wizard.soil == nil ? nil : .declaredHigh,
                    action: onEdit
                )

                Divider().overlay(ArboreDesign.Colors.border)

                GardenProfileRow(
                    icon: "mappin.and.ellipse",
                    title: L10n.t("GARDEN_PROFILE_LOCATION"),
                    value: GardenSiteProfileResolver.locationText(wizard.location),
                    metadata: GardenSiteProfileResolver.locationMetadata(wizard.location),
                    action: onEdit
                )

                Divider().overlay(ArboreDesign.Colors.border)

                GardenProfileRow(
                    icon: "wind",
                    title: L10n.t("GARDEN_PROFILE_WIND"),
                    value: profile.wind.map { GardenSiteProfileResolver.windText($0.level) },
                    metadata: profile.wind?.metadata,
                    action: onEdit
                )

                Divider().overlay(ArboreDesign.Colors.border)

                GardenProfileRow(
                    icon: "arrow.up.and.down",
                    title: L10n.t("GARDEN_PROFILE_HEIGHT"),
                    value: profile.availableHeight.map { String(format: "%.2f m", $0.meters) },
                    metadata: profile.availableHeight?.metadata,
                    action: onEdit
                )

                Divider().overlay(ArboreDesign.Colors.border)

                GardenProfileRow(
                    icon: "leaf.circle",
                    title: L10n.t("GARDEN_PROFILE_ZONES"),
                    value: GardenSiteProfileResolver.zonesText(profile.plantingZones),
                    metadata: profile.plantingZones.isEmpty ? nil : .declaredHigh,
                    action: onEdit
                )
            }
            .background(ArboreDesign.Colors.softSurface.opacity(0.52))
            .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))

            Button(action: onRemeasure) {
                Label(L10n.t("GARDEN_PROFILE_REDO_DIMENSIONS"), systemImage: "viewfinder")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(ArboreDesign.Colors.primaryButton)
                    .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                Label(L10n.t("GARDEN_PROFILE_REVIEW"), systemImage: "pencil")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(ArboreDesign.Colors.primaryGreen.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(ArboreDesign.Spacing.md)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }
}

private struct GardenProfileRow: View {
    let icon: String
    let title: String
    let value: String?
    let metadata: GardenValueMetadataDTO?
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: ArboreDesign.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                    .frame(width: 32, height: 32)
                    .background(ArboreDesign.Colors.primaryGreen.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ArboreDesign.Colors.textSecondary)

                    Text(value ?? L10n.t("GARDEN_PROFILE_UNAVAILABLE"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(value == nil ? ArboreDesign.Colors.textSecondary : ArboreDesign.Colors.textPrimary)
                        .multilineTextAlignment(.leading)

                    if let metadata {
                        HStack(spacing: 5) {
                            GardenMetadataBadge(text: GardenSiteProfileResolver.sourceText(metadata.source))
                            GardenMetadataBadge(text: GardenSiteProfileResolver.confidenceText(metadata.confidence))
                        }
                    } else {
                        Text(L10n.t("GARDEN_PROFILE_ADD_MANUALLY"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(ArboreDesign.Colors.primaryGreen)
                    }
                }

                Spacer(minLength: 4)

                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ArboreDesign.Colors.textSecondary.opacity(0.7))
                }
            }
            .padding(.horizontal, ArboreDesign.Spacing.sm)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

private struct GardenMetadataBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(ArboreDesign.Colors.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(ArboreDesign.Colors.background.opacity(0.75))
            .clipShape(Capsule())
    }
}

struct GardenSpaceProfileEditor: View {
    let initialWizard: GardenWizardDTO
    let area: Float
    let perimeter: Float
    let boundaryPoints: [[Float]]
    let onRemeasure: () -> Void
    let onSave: (GardenWizardDTO) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var wizard: GardenWizardDTO
    @State private var profile: GardenSiteProfileDTO
    @State private var selectedSpace: GardenSpaceType?
    @State private var selectedOrientation: GardenCardinalDirection?
    @State private var selectedSunlight: GardenSunlightBand?
    @State private var selectedSoil: SoilType?
    @State private var selectedWind: GardenWindLevelDTO?
    @State private var heightText: String
    @State private var cityText: String
    @State private var removeLocation = false
    @State private var isSaving = false
    @State private var saveError: String?

    init(
        initialWizard: GardenWizardDTO,
        area: Float,
        perimeter: Float,
        boundaryPoints: [[Float]],
        onRemeasure: @escaping () -> Void,
        onSave: @escaping (GardenWizardDTO) async throws -> Void
    ) {
        self.initialWizard = initialWizard
        self.area = area
        self.perimeter = perimeter
        self.boundaryPoints = boundaryPoints
        self.onRemeasure = onRemeasure
        self.onSave = onSave

        let resolved = GardenSiteProfileResolver.resolvedProfile(for: initialWizard)
        _wizard = State(initialValue: initialWizard)
        _profile = State(initialValue: resolved)
        _selectedSpace = State(initialValue: GardenSpaceType(rawValue: initialWizard.spaceType))
        _selectedOrientation = State(initialValue: resolved.orientation.map { GardenCardinalDirection(degrees: $0.degrees) })
        _selectedSunlight = State(initialValue: resolved.sunlight.map(GardenSunlightBand.init))
        _selectedSoil = State(initialValue: initialWizard.soil.flatMap { SoilType(rawValue: $0) })
        _selectedWind = State(initialValue: resolved.wind?.level)
        _heightText = State(initialValue: resolved.availableHeight.map { String(format: "%.2f", $0.meters) } ?? "")
        _cityText = State(initialValue: initialWizard.location?.city ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.t("GARDEN_PROFILE_SPACE"), selection: $selectedSpace) {
                        Text(L10n.t("GARDEN_PROFILE_UNAVAILABLE")).tag(Optional<GardenSpaceType>.none)
                        ForEach(GardenSpaceType.allCases) { space in
                            Text(space.title).tag(Optional(space))
                        }
                    }
                } header: {
                    Text(L10n.t("GARDEN_PROFILE_SPACE_SECTION"))
                }

                Section {
                    LabeledContent(L10n.t("GARDEN_STAT_SURFACE"), value: area > 0 ? String(format: "%.2f m²", area) : L10n.t("GARDEN_PROFILE_UNAVAILABLE"))
                    LabeledContent(L10n.t("GARDEN_STAT_PERIMETER"), value: perimeter > 0 ? String(format: "%.2f m", perimeter) : L10n.t("GARDEN_PROFILE_UNAVAILABLE"))

                    Button {
                        dismiss()
                        onRemeasure()
                    } label: {
                        Label(L10n.t("GARDEN_PROFILE_REMEASURE"), systemImage: "viewfinder")
                    }
                } header: {
                    Text(L10n.t("GARDEN_PROFILE_MEASUREMENTS_SECTION"))
                } footer: {
                    Text(L10n.t("GARDEN_PROFILE_MEASUREMENTS_HELP"))
                }

                Section {
                    Picker(L10n.t("GARDEN_PROFILE_ORIENTATION"), selection: $selectedOrientation) {
                        Text(L10n.t("GARDEN_PROFILE_UNAVAILABLE")).tag(Optional<GardenCardinalDirection>.none)
                        ForEach(GardenCardinalDirection.allCases) { direction in
                            Text(direction.title).tag(Optional(direction))
                        }
                    }

                    Picker(L10n.t("GARDEN_PROFILE_SUNLIGHT"), selection: $selectedSunlight) {
                        Text(L10n.t("GARDEN_PROFILE_UNAVAILABLE")).tag(Optional<GardenSunlightBand>.none)
                        ForEach(GardenSunlightBand.allCases) { band in
                            Text(band.title).tag(Optional(band))
                        }
                    }

                    Picker(L10n.t("GARDEN_PROFILE_WIND"), selection: $selectedWind) {
                        Text(L10n.t("GARDEN_PROFILE_UNAVAILABLE")).tag(Optional<GardenWindLevelDTO>.none)
                        ForEach(GardenWindLevelDTO.allCases, id: \.self) { wind in
                            Text(GardenSiteProfileResolver.windText(wind)).tag(Optional(wind))
                        }
                    }

                    Picker(L10n.t("GARDEN_PROFILE_SOIL"), selection: $selectedSoil) {
                        Text(L10n.t("GARDEN_PROFILE_UNAVAILABLE")).tag(Optional<SoilType>.none)
                        ForEach(SoilType.allCases) { soil in
                            Text(soil.title).tag(Optional(soil))
                        }
                    }

                    HStack {
                        Text(L10n.t("GARDEN_PROFILE_HEIGHT"))
                        Spacer()
                        TextField(L10n.t("GARDEN_PROFILE_UNAVAILABLE"), text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                        Text("m")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L10n.t("GARDEN_PROFILE_CONDITIONS_SECTION"))
                } footer: {
                    Text(L10n.t("GARDEN_PROFILE_DECLARED_HELP"))
                }

                Section {
                    if let location = initialWizard.location, !removeLocation {
                        LabeledContent(
                            L10n.t("GARDEN_PROFILE_CURRENT_LOCATION"),
                            value: GardenSiteProfileResolver.locationText(location) ?? L10n.t("GARDEN_PROFILE_UNAVAILABLE")
                        )
                    }

                    TextField(L10n.t("GARDEN_LOCATION_CITY_PLACEHOLDER"), text: $cityText)
                        .textContentType(.addressCity)

                    if initialWizard.location != nil && !removeLocation {
                        Button(L10n.t("GARDEN_PROFILE_REMOVE_LOCATION"), role: .destructive) {
                            removeLocation = true
                            cityText = ""
                        }
                    }
                } header: {
                    Text(L10n.t("GARDEN_PROFILE_LOCATION"))
                } footer: {
                    Text(L10n.t("GARDEN_LOCATION_CITY_DESCRIPTION"))
                }

                Section {
                    NavigationLink {
                        GardenPlantingZonesEditor(
                            zones: $profile.plantingZones,
                            boundaryPoints: boundaryPoints
                        )
                    } label: {
                        LabeledContent(
                            L10n.t("GARDEN_PROFILE_ZONES"),
                            value: GardenSiteProfileResolver.zonesText(profile.plantingZones) ?? L10n.t("GARDEN_PROFILE_UNAVAILABLE")
                        )
                    }
                } footer: {
                    Text(boundaryPoints.count >= 3 ? L10n.t("GARDEN_PROFILE_ZONES_HELP") : L10n.t("GARDEN_PROFILE_ZONES_NEED_SCAN"))
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.t("GARDEN_PROFILE_EDIT_TITLE"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("COMMON_CANCEL")) { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(L10n.t("COMMON_SAVE"))
                                .bold()
                        }
                    }
                    .disabled(isSaving || !heightIsValid)
                }
            }
        }
    }

    private var heightIsValid: Bool {
        let trimmed = heightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let value = parsedHeight else { return false }
        return value > 0 && value <= 100
    }

    private var parsedHeight: Double? {
        Double(heightText.replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        let declared = GardenValueMetadataDTO.declaredHigh

        wizard.spaceType = selectedSpace?.rawValue ?? ""
        wizard.soil = selectedSoil?.rawValue
        let previousOrientation = profile.orientation
        let previousDirection = previousOrientation.map { GardenCardinalDirection(degrees: $0.degrees) }
        if selectedOrientation != previousDirection {
            profile.orientation = selectedOrientation.map {
                GardenOrientationDTO(degrees: $0.degrees, metadata: declared)
            }
        }

        let previousSunlight = profile.sunlight
        let previousSunlightBand = previousSunlight.map(GardenSunlightBand.init)
        if selectedSunlight != previousSunlightBand {
            profile.sunlight = selectedSunlight.map {
                GardenSunlightDTO(minimumHours: $0.minimumHours, maximumHours: $0.maximumHours, metadata: declared)
            }
        }

        if selectedWind != profile.wind?.level {
            profile.wind = selectedWind.map {
                GardenWindDTO(level: $0, metadata: declared)
            }
        }

        if let parsedHeight {
            if profile.availableHeight.map({ abs($0.meters - parsedHeight) > 0.001 }) ?? true {
                profile.availableHeight = GardenAvailableHeightDTO(meters: parsedHeight, metadata: declared)
            }
        } else {
            profile.availableHeight = nil
        }

        let initialZones = GardenSiteProfileResolver
            .resolvedProfile(for: initialWizard)
            .plantingZones
            .reduce(into: [String: GardenPlantingZoneDTO]()) { result, zone in
                result[zone.id] = zone
            }
        profile.plantingZones = profile.plantingZones.map { zone in
            guard let initial = initialZones[zone.id],
                  initial.name == zone.name,
                  initial.points == zone.points,
                  initial.isExcluded == zone.isExcluded else {
                var declaredZone = zone
                declaredZone.metadata = declared
                return declaredZone
            }
            return zone
        }

        let trimmedCity = cityText.trimmingCharacters(in: .whitespacesAndNewlines)
        if removeLocation {
            wizard.location = nil
        } else if !trimmedCity.isEmpty, trimmedCity != initialWizard.location?.city {
            wizard.location = .manualCity(trimmedCity)
        }

        wizard.siteProfile = profile
        saveError = nil
        isSaving = true

        Task {
            do {
                try await onSave(wizard)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    saveError = L10n.t("GARDEN_PROFILE_SAVE_ERROR")
                    isSaving = false
                }
            }
        }
    }
}

private enum GardenCardinalDirection: String, CaseIterable, Identifiable {
    case north, northEast, east, southEast, south, southWest, west, northWest

    var id: String { rawValue }

    init(degrees: Double) {
        let normalized = GardenSiteProfileResolver.normalizedDegrees(degrees)
        let index = Int((normalized + 22.5) / 45).quotientAndRemainder(dividingBy: 8).remainder
        self = Self.allCases[index]
    }

    var degrees: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0) * 45
    }

    var title: String {
        GardenSiteProfileResolver.orientationText(degrees)
    }
}

private enum GardenSunlightBand: String, CaseIterable, Identifiable {
    case shade, partial, sun

    var id: String { rawValue }

    init(_ sunlight: GardenSunlightDTO) {
        if sunlight.maximumHours <= 3 {
            self = .shade
        } else if sunlight.minimumHours >= 6 {
            self = .sun
        } else {
            self = .partial
        }
    }

    var minimumHours: Double {
        switch self {
        case .shade: return 0
        case .partial: return 3
        case .sun: return 6
        }
    }

    var maximumHours: Double {
        switch self {
        case .shade: return 3
        case .partial: return 6
        case .sun: return 12
        }
    }

    var title: String {
        switch self {
        case .shade: return L10n.t("GARDEN_PROFILE_SUN_SHADE")
        case .partial: return L10n.t("GARDEN_PROFILE_SUN_PARTIAL")
        case .sun: return L10n.t("GARDEN_PROFILE_SUN_FULL")
        }
    }
}

struct GardenPlantingZonesEditor: View {
    @Binding var zones: [GardenPlantingZoneDTO]
    let boundaryPoints: [[Float]]

    @State private var editingZone: GardenPlantingZoneDTO?

    var body: some View {
        List {
            if zones.isEmpty {
                ContentUnavailableView(
                    L10n.t("GARDEN_PROFILE_ZONES_EMPTY"),
                    systemImage: "leaf.circle",
                    description: Text(L10n.t("GARDEN_PROFILE_ZONES_EMPTY_HELP"))
                )
            } else {
                ForEach($zones) { $zone in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(zone.name)
                                    .font(.headline)
                                Text(zone.isExcluded ? L10n.t("GARDEN_PROFILE_ZONE_EXCLUDED") : L10n.t("GARDEN_PROFILE_ZONE_USABLE"))
                                    .font(.caption)
                                    .foregroundStyle(zone.isExcluded ? .orange : .secondary)
                            }

                            Spacer()

                            Button {
                                editingZone = zone
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                        }

                        Toggle(L10n.t("GARDEN_PROFILE_ZONE_EXCLUDE"), isOn: $zone.isExcluded)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    zones.remove(atOffsets: offsets)
                }
            }
        }
        .navigationTitle(L10n.t("GARDEN_PROFILE_ZONES"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingZone = GardenPlantingZoneDTO(
                        id: UUID().uuidString,
                        name: L10n.f("GARDEN_PROFILE_ZONE_NAME_FORMAT", zones.count + 1),
                        points: [],
                        isExcluded: false,
                        metadata: .declaredHigh
                    )
                } label: {
                    Label(L10n.t("GARDEN_PROFILE_ZONE_ADD"), systemImage: "plus")
                }
                .disabled(boundaryPoints.count < 3)
            }
        }
        .sheet(item: $editingZone) { zone in
            GardenZonePolygonEditor(
                zone: zone,
                boundaryPoints: boundaryPoints,
                onSave: { editedZone in
                    if let index = zones.firstIndex(where: { $0.id == editedZone.id }) {
                        zones[index] = editedZone
                    } else {
                        zones.append(editedZone)
                    }
                }
            )
        }
    }
}

private struct GardenZonePolygonEditor: View {
    let initialZone: GardenPlantingZoneDTO
    let boundaryPoints: [[Float]]
    let onSave: (GardenPlantingZoneDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var points: [[Float]]

    init(
        zone: GardenPlantingZoneDTO,
        boundaryPoints: [[Float]],
        onSave: @escaping (GardenPlantingZoneDTO) -> Void
    ) {
        initialZone = zone
        self.boundaryPoints = boundaryPoints
        self.onSave = onSave
        _name = State(initialValue: zone.name)
        _points = State(initialValue: zone.points)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: ArboreDesign.Spacing.md) {
                TextField(L10n.t("GARDEN_PROFILE_ZONE_NAME"), text: $name)
                    .textFieldStyle(.roundedBorder)

                Text(L10n.t("GARDEN_PROFILE_ZONE_DRAW_HELP"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GardenZoneDrawingCanvas(boundaryPoints: boundaryPoints, points: $points)
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                HStack {
                    Button {
                        points = boundaryPoints
                    } label: {
                        Label(L10n.t("GARDEN_PROFILE_ZONE_FULL_SPACE"), systemImage: "square.dashed")
                    }

                    Spacer()

                    Button {
                        _ = points.popLast()
                    } label: {
                        Label(L10n.t("GARDEN_PROFILE_ZONE_UNDO"), systemImage: "arrow.uturn.backward")
                    }
                    .disabled(points.isEmpty)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(ArboreDesign.Colors.background.ignoresSafeArea())
            .navigationTitle(L10n.t("GARDEN_PROFILE_ZONE_DRAW"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("COMMON_CANCEL")) { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("COMMON_SAVE")) {
                        var edited = initialZone
                        edited.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        edited.points = points
                        edited.metadata = .declaredHigh
                        onSave(edited)
                        dismiss()
                    }
                    .bold()
                    .disabled(points.count < 3 || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct GardenZoneDrawingCanvas: View {
    let boundaryPoints: [[Float]]
    @Binding var points: [[Float]]

    var body: some View {
        GeometryReader { geometry in
            let projection = GardenZoneProjection(boundaryPoints: boundaryPoints, size: geometry.size)

            Canvas { context, _ in
                let boundaryPath = projection.path(for: boundaryPoints)
                context.fill(boundaryPath, with: .color(ArboreDesign.Colors.primaryGreen.opacity(0.08)))
                context.stroke(boundaryPath, with: .color(ArboreDesign.Colors.textSecondary), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))

                if points.count >= 2 {
                    let zonePath = projection.path(for: points, closed: points.count >= 3)
                    if points.count >= 3 {
                        context.fill(zonePath, with: .color(ArboreDesign.Colors.primaryGreen.opacity(0.25)))
                    }
                    context.stroke(zonePath, with: .color(ArboreDesign.Colors.primaryGreen), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                for point in points {
                    let center = projection.screenPoint(for: point)
                    let rect = CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: rect), with: .color(ArboreDesign.Colors.primaryGreen))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard projection.contains(value.location) else { return }
                        points.append(projection.worldPoint(for: value.location))
                    }
            )
        }
        .background(ArboreDesign.Colors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }
}

private struct GardenZoneProjection {
    let boundaryPoints: [[Float]]
    let size: CGSize
    private let padding: CGFloat = 28

    private var validBoundary: [[Float]] {
        boundaryPoints.filter { $0.count >= 3 }
    }

    private var minX: Float { validBoundary.map { $0[0] }.min() ?? -1 }
    private var maxX: Float { validBoundary.map { $0[0] }.max() ?? 1 }
    private var minZ: Float { validBoundary.map { $0[2] }.min() ?? -1 }
    private var maxZ: Float { validBoundary.map { $0[2] }.max() ?? 1 }

    private var scale: CGFloat {
        let width = max(CGFloat(maxX - minX), 0.01)
        let height = max(CGFloat(maxZ - minZ), 0.01)
        return min(max(size.width - padding * 2, 1) / width, max(size.height - padding * 2, 1) / height)
    }

    private var origin: CGPoint {
        let drawnWidth = CGFloat(maxX - minX) * scale
        let drawnHeight = CGFloat(maxZ - minZ) * scale
        return CGPoint(x: (size.width - drawnWidth) / 2, y: (size.height - drawnHeight) / 2)
    }

    func screenPoint(for point: [Float]) -> CGPoint {
        guard point.count >= 3 else { return .zero }
        return CGPoint(
            x: origin.x + CGFloat(point[0] - minX) * scale,
            y: origin.y + CGFloat(point[2] - minZ) * scale
        )
    }

    func worldPoint(for point: CGPoint) -> [Float] {
        let x = Float((point.x - origin.x) / scale) + minX
        let z = Float((point.y - origin.y) / scale) + minZ
        let y = validBoundary.first.map { $0.count > 1 ? $0[1] : 0 } ?? 0
        return [x, y, z]
    }

    func path(for points: [[Float]], closed: Bool = true) -> Path {
        Path { path in
            for (index, point) in points.filter({ $0.count >= 3 }).enumerated() {
                let screen = screenPoint(for: point)
                index == 0 ? path.move(to: screen) : path.addLine(to: screen)
            }
            if closed { path.closeSubpath() }
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        path(for: validBoundary).contains(point)
    }
}

enum GardenSiteProfileResolver {
    static func resolvedProfile(for wizard: GardenWizardDTO) -> GardenSiteProfileDTO {
        var profile = wizard.siteProfile ?? GardenSiteProfileDTO()

        if profile.orientation == nil, let yaw = wizard.lightExposure?.magneticYawRadians {
            profile.orientation = GardenOrientationDTO(
                degrees: normalizedDegrees(yaw * 180 / .pi),
                metadata: GardenValueMetadataDTO(source: .measured, confidence: .medium)
            )
        }

        if profile.sunlight == nil, let exposure = wizard.exposure?.lowercased() {
            let metadata = GardenValueMetadataDTO.declaredHigh
            if exposure.contains("6h") || exposure.contains("soleil direct") || exposure == "fullsun" {
                profile.sunlight = GardenSunlightDTO(minimumHours: 6, maximumHours: 12, metadata: metadata)
            } else if exposure.contains("mi-ombre") || exposure.contains("partial") {
                profile.sunlight = GardenSunlightDTO(minimumHours: 3, maximumHours: 6, metadata: metadata)
            } else if exposure.contains("ombr") || exposure.contains("shade") {
                profile.sunlight = GardenSunlightDTO(minimumHours: 0, maximumHours: 3, metadata: metadata)
            }
        }

        if profile.wind == nil, let declaredWind = wizard.conditionalAnswers?.windExposure {
            let level: GardenWindLevelDTO
            switch declaredWind {
            case .sheltered:
                level = .sheltered
            case .sometimesWindy:
                level = .moderate
            case .veryExposed:
                level = .strong
            }
            profile.wind = GardenWindDTO(
                level: level,
                metadata: .declaredHigh
            )
        }

        return profile
    }

    static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    static func orientationText(_ degrees: Double) -> String {
        let labels = [
            L10n.t("GARDEN_PROFILE_NORTH"),
            L10n.t("GARDEN_PROFILE_NORTH_EAST"),
            L10n.t("GARDEN_PROFILE_EAST"),
            L10n.t("GARDEN_PROFILE_SOUTH_EAST"),
            L10n.t("GARDEN_PROFILE_SOUTH"),
            L10n.t("GARDEN_PROFILE_SOUTH_WEST"),
            L10n.t("GARDEN_PROFILE_WEST"),
            L10n.t("GARDEN_PROFILE_NORTH_WEST")
        ]
        let index = Int((normalizedDegrees(degrees) + 22.5) / 45).quotientAndRemainder(dividingBy: 8).remainder
        return labels[index]
    }

    static func sunlightText(_ sunlight: GardenSunlightDTO) -> String {
        if sunlight.maximumHours <= 3 { return L10n.t("GARDEN_PROFILE_SUN_SHADE") }
        if sunlight.minimumHours >= 6 { return L10n.t("GARDEN_PROFILE_SUN_FULL") }
        return L10n.t("GARDEN_PROFILE_SUN_PARTIAL")
    }

    static func windText(_ wind: GardenWindLevelDTO) -> String {
        switch wind {
        case .sheltered: return L10n.t("GARDEN_PROFILE_WIND_SHELTERED")
        case .light: return L10n.t("GARDEN_PROFILE_WIND_LIGHT")
        case .moderate: return L10n.t("GARDEN_PROFILE_WIND_MODERATE")
        case .strong: return L10n.t("GARDEN_PROFILE_WIND_STRONG")
        }
    }

    static func spaceTitle(_ rawValue: String) -> String? {
        GardenSpaceType(rawValue: rawValue)?.title ?? (rawValue.isEmpty ? nil : rawValue)
    }

    static func locationText(_ location: GardenLocationDTO?) -> String? {
        guard let location else { return nil }
        if let city = location.city, !city.isEmpty { return city }
        if let latitude = location.latitude, let longitude = location.longitude {
            return String(format: "%.2f, %.2f", latitude, longitude)
        }
        return nil
    }

    static func locationMetadata(_ location: GardenLocationDTO?) -> GardenValueMetadataDTO? {
        guard let location else { return nil }
        switch location.source {
        case .deviceApproximate:
            return GardenValueMetadataDTO(source: .measured, confidence: .medium)
        case .manualCity:
            return .declaredHigh
        }
    }

    static func zonesText(_ zones: [GardenPlantingZoneDTO]) -> String? {
        guard !zones.isEmpty else { return nil }
        let usableCount = zones.filter { !$0.isExcluded }.count
        return L10n.f("GARDEN_PROFILE_ZONES_FORMAT", usableCount)
    }

    static func sourceText(_ source: GardenDataSourceDTO) -> String {
        switch source {
        case .measured: return L10n.t("GARDEN_PROFILE_SOURCE_MEASURED")
        case .inferred: return L10n.t("GARDEN_PROFILE_SOURCE_INFERRED")
        case .declared: return L10n.t("GARDEN_PROFILE_SOURCE_DECLARED")
        case .regionalEstimate: return L10n.t("GARDEN_PROFILE_SOURCE_REGIONAL")
        }
    }

    static func confidenceText(_ confidence: GardenDataConfidenceDTO) -> String {
        switch confidence {
        case .high: return L10n.t("GARDEN_PROFILE_CONFIDENCE_HIGH")
        case .medium: return L10n.t("GARDEN_PROFILE_CONFIDENCE_MEDIUM")
        case .low: return L10n.t("GARDEN_PROFILE_CONFIDENCE_LOW")
        }
    }
}

extension GardenValueMetadataDTO {
    static let measuredHigh = GardenValueMetadataDTO(source: .measured, confidence: .high)
    static let declaredHigh = GardenValueMetadataDTO(source: .declared, confidence: .high)
}
