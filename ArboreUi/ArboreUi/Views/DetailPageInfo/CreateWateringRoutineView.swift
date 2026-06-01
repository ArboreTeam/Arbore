import SwiftUI

enum GardenRoutinePlanningKind: Hashable, Identifiable {
    case watering
    case care(GardenCareKind)

    static var allPlanningCases: [GardenRoutinePlanningKind] {
        [.watering] + GardenCareKind.allCases.map { .care($0) }
    }

    var id: String {
        switch self {
        case .watering:
            return "watering"
        case .care(let kind):
            return "care-\(kind.rawValue)"
        }
    }

    var displayName: String {
        switch self {
        case .watering:
            return "Arroser"
        case .care(let kind):
            return kind.displayName
        }
    }

    var subtitle: String {
        switch self {
        case .watering:
            return "Planifiez une routine d’arrosage régulière."
        case .care(let kind):
            switch kind {
            case .pruneLeaves:
                return "Programmez la taille des feuilles abîmées."
            case .cleanLeaves:
                return "Gardez les feuilles propres et respirantes."
            case .fertilize:
                return "Ajoutez un rappel pour l’apport d’engrais."
            case .repot:
                return "Anticipez le rempotage et le substrat."
            case .pestCheck:
                return "Surveillez les signes de parasites."
            case .rotatePot:
                return "Tournez la plante pour équilibrer la lumière."
            case .soilCheck:
                return "Vérifiez l’état du sol et l’humidité."
            case .custom:
                return "Créez votre propre action récurrente."
            }
        }
    }

    var icon: String {
        switch self {
        case .watering:
            return "drop.fill"
        case .care(let kind):
            return kind.icon
        }
    }

    var tintHex: String {
        switch self {
        case .watering:
            return "#38BDF8"
        case .care(let kind):
            return kind.tintHex
        }
    }

    var tintColor: Color {
        Color(hex: tintHex)
    }

    var defaultFrequency: WateringFrequency {
        switch self {
        case .watering:
            return .weekly
        case .care:
            return .custom
        }
    }

    var defaultCustomDays: Int {
        switch self {
        case .watering:
            return WateringFrequency.weekly.days
        case .care(let kind):
            return kind.defaultIntervalDays
        }
    }

    var detailSectionIcon: String {
        switch self {
        case .watering:
            return "drop.triangle"
        case .care(let kind):
            return kind.icon
        }
    }

    var detailSectionTitle: String {
        switch self {
        case .watering:
            return NSLocalizedString("ROUTINE_AMOUNT_LABEL", comment: "")
        case .care(let kind):
            switch kind {
            case .pruneLeaves:
                return "Taille prévue"
            case .cleanLeaves:
                return "Nettoyage prévu"
            case .fertilize:
                return "Engrais / dosage"
            case .repot:
                return "Pot / substrat"
            case .pestCheck:
                return "Points à vérifier"
            case .rotatePot:
                return "Rotation"
            case .soilCheck:
                return "Contrôle du sol"
            case .custom:
                return "Détail de l’action"
            }
        }
    }

    var detailPlaceholder: String {
        switch self {
        case .watering:
            return NSLocalizedString("ROUTINE_AMOUNT_PLACEHOLDER", comment: "")
        case .care(let kind):
            switch kind {
            case .pruneLeaves:
                return "Ex : retirer les feuilles jaunes"
            case .cleanLeaves:
                return "Ex : chiffon humide, dessus des feuilles"
            case .fertilize:
                return "Ex : 1/2 dose d’engrais liquide"
            case .repot:
                return "Ex : pot +2 cm, terreau drainant"
            case .pestCheck:
                return "Ex : vérifier sous les feuilles"
            case .rotatePot:
                return "Ex : tourner d’un quart de tour"
            case .soilCheck:
                return "Ex : vérifier les 3 premiers cm"
            case .custom:
                return "Ex : brumiser, tuteurer, déplacer..."
            }
        }
    }

    var requiresCustomTitle: Bool {
        if case .care(.custom) = self {
            return true
        }
        return false
    }

    var isWatering: Bool {
        if case .watering = self {
            return true
        }
        return false
    }
}

struct CreateWateringRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var routineStore = WateringRoutineStore.shared

    // Props from parent
    let plantName: String
    let waterInfo: WaterInfo?
    var gardenId: String?
    var plantId: String?
    var availablePlants: [PersistedPlant]
    var allowedActions: [GardenRoutinePlanningKind]
    var onRoutineSaved: ((WateringRoutine) -> Void)?
    var onCareRoutineSaved: ((PlantCareRoutine) -> Void)?

    // Form state
    @State private var selectedAction: GardenRoutinePlanningKind
    @State private var selectedPlantId: String
    @State private var selectedFrequency: WateringFrequency
    @State private var customDays: Int
    @State private var firstActionDate = Date()
    @State private var reminderTime = Date()
    @State private var detailValue: String = ""
    @State private var customActionTitle: String = ""
    @State private var notes: String = ""
    @State private var addToCalendar: Bool = true

    // UI state
    @State private var showingSuccessAlert = false
    @State private var showingCalendarDeniedAlert = false
    @State private var showingErrorAlert = false
    @State private var isCreating = false
    @State private var calendarSuccessMessage: String = ""
    @State private var errorMessage: String = ""

    init(
        plantName: String,
        waterInfo: WaterInfo?,
        gardenId: String? = nil,
        plantId: String? = nil,
        availablePlants: [PersistedPlant] = [],
        initialPlantId: String? = nil,
        allowedActions: [GardenRoutinePlanningKind] = [.watering],
        initialAction: GardenRoutinePlanningKind = .watering,
        onRoutineSaved: ((WateringRoutine) -> Void)? = nil,
        onCareRoutineSaved: ((PlantCareRoutine) -> Void)? = nil
    ) {
        let resolvedActions = allowedActions.isEmpty ? [.watering] : allowedActions
        let resolvedAction = resolvedActions.contains(initialAction) ? initialAction : resolvedActions[0]
        let resolvedPlantId = initialPlantId ?? plantId ?? availablePlants.first?.plantID ?? ""

        self.plantName = plantName
        self.waterInfo = waterInfo
        self.gardenId = gardenId
        self.plantId = plantId
        self.availablePlants = availablePlants
        self.allowedActions = resolvedActions
        self.onRoutineSaved = onRoutineSaved
        self.onCareRoutineSaved = onCareRoutineSaved

        _selectedAction = State(initialValue: resolvedAction)
        _selectedPlantId = State(initialValue: resolvedPlantId)
        _selectedFrequency = State(initialValue: resolvedAction.defaultFrequency)
        _customDays = State(initialValue: resolvedAction.defaultCustomDays)
    }

    var body: some View {
        NavigationView {
            ZStack {
                themeManager.backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        if allowedActions.count > 1 {
                            actionSection
                        }
                        plantSection
                        frequencySection
                        if selectedFrequency == .custom {
                            customDaysSection
                        }
                        firstDateSection
                        timeSection
                        detailSection
                        notesSection
                        calendarToggleSection
                        createButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }

                if isCreating {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)

                            Text(NSLocalizedString("ROUTINE_CREATING", comment: ""))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(32)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    }
                }
            }
            .navigationTitle("Planifier une action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(primaryTextColor)
                    }
                    .disabled(isCreating)
                }
            }
            .alert(NSLocalizedString("ROUTINE_SUCCESS_TITLE", comment: ""), isPresented: $showingSuccessAlert) {
                Button(NSLocalizedString("ROUTINE_SUCCESS_OK", comment: ""), role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(calendarSuccessMessage)
            }
            .alert(NSLocalizedString("ROUTINE_CALENDAR_DENIED_TITLE", comment: ""), isPresented: $showingCalendarDeniedAlert) {
                Button(NSLocalizedString("ROUTINE_CALENDAR_DENIED_SETTINGS", comment: "")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button(NSLocalizedString("ROUTINE_SUCCESS_OK", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("ROUTINE_CALENDAR_DENIED_MESSAGE", comment: ""))
            }
            .alert(NSLocalizedString("ROUTINE_CALENDAR_ERROR", comment: ""), isPresented: $showingErrorAlert) {
                Button(NSLocalizedString("ROUTINE_SUCCESS_OK", comment: ""), role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            if selectedAction.isWatering {
                prefillFromWaterInfo()
            }
        }
        .onChange(of: selectedAction) { _, newAction in
            selectedFrequency = newAction.defaultFrequency
            customDays = newAction.defaultCustomDays
            detailValue = ""

            if !newAction.requiresCustomTitle {
                customActionTitle = ""
            }
            if newAction.isWatering {
                prefillFromWaterInfo()
            }
        }
    }

    // MARK: - Colors

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
    }

    private var cardBackgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.11, green: 0.11, blue: 0.12)
        : Color(red: 0.95, green: 0.95, blue: 0.96)
    }

    private var actionTint: Color {
        selectedAction.tintColor
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [actionTint.opacity(0.86), actionTint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: actionTint.opacity(0.35), radius: 12, x: 0, y: 6)

                Image(systemName: selectedAction.icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text(actionTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(primaryTextColor)
                .multilineTextAlignment(.center)

            Text("\(selectedPlantName) • \(selectedAction.subtitle)")
                .font(.system(size: 15))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: "checklist",
                title: "Action à planifier",
                tint: actionTint
            )

            Menu {
                ForEach(allowedActions) { action in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.76)) {
                            selectedAction = action
                        }
                    } label: {
                        Label(action.displayName, systemImage: action.icon)
                    }
                }
            } label: {
                selectionRow(
                    icon: selectedAction.icon,
                    title: "Action",
                    value: actionTitle,
                    tint: actionTint,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)

            if selectedAction.requiresCustomTitle {
                TextField("Nom de l’action", text: $customActionTitle)
                    .padding(16)
                    .background(cardBackgroundColor)
                    .cornerRadius(12)
                    .foregroundColor(primaryTextColor)
                    .font(.system(size: 16))
            }
        }
    }

    // MARK: - Plant Section

    private var plantSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: "leaf",
                title: "Plante",
                tint: actionTint
            )

            if availablePlants.isEmpty {
                selectionRow(
                    icon: "leaf.fill",
                    title: "Plante",
                    value: selectedPlantName,
                    tint: actionTint,
                    showsChevron: false
                )
            } else {
                Menu {
                    ForEach(availablePlants, id: \.plantID) { plant in
                        Button {
                            selectedPlantId = plant.plantID
                        } label: {
                            Label(plant.plantName, systemImage: "leaf")
                        }
                    }
                } label: {
                    selectionRow(
                        icon: "leaf.fill",
                        title: "Plante",
                        value: selectedPlantName,
                        tint: actionTint,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Frequency Section

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: "calendar",
                title: NSLocalizedString("ROUTINE_FREQUENCY_LABEL", comment: ""),
                tint: actionTint
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(WateringFrequency.allCases, id: \.self) { freq in
                    FrequencyCard(
                        frequency: freq,
                        isSelected: selectedFrequency == freq,
                        tint: actionTint
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFrequency = freq
                            if freq != .custom {
                                customDays = freq.days
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Custom Days

    private var customDaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: "calendar.badge.plus",
                title: NSLocalizedString("ROUTINE_CUSTOM_DAYS_LABEL", comment: ""),
                tint: actionTint
            )

            HStack {
                Button(action: {
                    if customDays > 1 {
                        customDays -= 1
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(actionTint)
                }

                Spacer()

                VStack(spacing: 4) {
                    Text("\(customDays)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(primaryTextColor)

                    Text(NSLocalizedString("ROUTINE_DAYS_UNIT", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(secondaryTextColor)
                }

                Spacer()

                Button(action: {
                    if customDays < 365 {
                        customDays += 1
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(actionTint)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .background(cardBackgroundColor)
            .cornerRadius(16)
        }
    }

    // MARK: - First Date Section

    private var firstDateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: "calendar.badge.clock",
                title: "Première date",
                tint: actionTint
            )

            DatePicker(
                "Commencer le",
                selection: $firstActionDate,
                displayedComponents: .date
            )
            .tint(actionTint)
            .padding(16)
            .background(cardBackgroundColor)
            .cornerRadius(16)
            .foregroundColor(primaryTextColor)
            .font(.system(size: 16, weight: .semibold))
        }
    }

    // MARK: - Time Section

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: "clock",
                title: NSLocalizedString("ROUTINE_TIME_LABEL", comment: ""),
                tint: actionTint
            )

            DatePicker(
                "",
                selection: $reminderTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(cardBackgroundColor)
            .cornerRadius(16)
            .tint(actionTint)
        }
    }

    // MARK: - Detail Section

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: selectedAction.detailSectionIcon,
                title: selectedAction.detailSectionTitle,
                tint: actionTint
            )

            TextField(
                selectedAction.detailPlaceholder,
                text: $detailValue
            )
            .padding(16)
            .background(cardBackgroundColor)
            .cornerRadius(12)
            .foregroundColor(primaryTextColor)
            .font(.system(size: 16))
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(
                icon: "note.text",
                title: NSLocalizedString("ROUTINE_NOTES_LABEL", comment: ""),
                tint: actionTint
            )

            TextEditor(text: $notes)
                .frame(height: 100)
                .padding(12)
                .background(cardBackgroundColor)
                .cornerRadius(12)
                .foregroundColor(primaryTextColor)
                .font(.system(size: 15))
                .overlay(
                    Group {
                        if notes.isEmpty {
                            Text(NSLocalizedString("ROUTINE_NOTES_PLACEHOLDER", comment: ""))
                                .foregroundColor(secondaryTextColor.opacity(0.5))
                                .font(.system(size: 15))
                                .padding(.top, 20)
                                .padding(.leading, 16)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
        }
    }

    // MARK: - Calendar Toggle

    private var calendarToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [actionTint.opacity(0.2), actionTint.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(actionTint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("ROUTINE_CALENDAR_TOGGLE", comment: ""))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(primaryTextColor)

                    Text(NSLocalizedString("ROUTINE_CALENDAR_TOGGLE_SUBTITLE", comment: ""))
                        .font(.system(size: 12))
                        .foregroundColor(secondaryTextColor)
                }

                Spacer()

                Toggle("", isOn: $addToCalendar)
                    .labelsHidden()
                    .tint(actionTint)
            }
            .padding(16)
            .background(cardBackgroundColor)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        addToCalendar ? actionTint.opacity(0.3) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
    }

    // MARK: - Create Button

    private var createButton: some View {
        Button(action: createRoutine) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                Text(NSLocalizedString("ROUTINE_CREATE_BUTTON", comment: ""))
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [actionTint.opacity(0.86), actionTint],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: actionTint.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .disabled(isCreateDisabled || isCreating)
        .opacity(isCreateDisabled || isCreating ? 0.6 : 1.0)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private var selectedPlant: PersistedPlant? {
        availablePlants.first(where: { $0.plantID == selectedPlantId }) ?? availablePlants.first
    }

    private var selectedPlantName: String {
        selectedPlant?.plantName ?? plantName
    }

    private var selectedPlantIdentifier: String? {
        selectedPlant?.plantID ?? plantId
    }

    private var actionTitle: String {
        if selectedAction.requiresCustomTitle {
            let trimmed = customActionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? selectedAction.displayName : trimmed
        }
        return selectedAction.displayName
    }

    private var isCreateDisabled: Bool {
        selectedPlantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || (selectedAction.requiresCustomTitle && customActionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var finalDays: Int {
        selectedFrequency == .custom ? customDays : selectedFrequency.days
    }

    private var firstScheduledDate: Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: reminderTime)
        return calendar.date(
            bySettingHour: timeComponents.hour ?? 9,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: firstActionDate
        ) ?? firstActionDate
    }

    private func selectionRow(
        icon: String,
        title: String,
        value: String,
        tint: Color,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(secondaryTextColor)

                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(secondaryTextColor)
            }
        }
        .padding(16)
        .background(cardBackgroundColor)
        .cornerRadius(16)
    }

    // MARK: - Actions

    private func prefillFromWaterInfo() {
        guard let waterInfo else { return }

        if let frequency = waterInfo.frequency?.lowercased() {
            if frequency.contains("jour") || frequency.contains("day") || frequency.contains("daily") {
                selectedFrequency = .daily
            } else if frequency.contains("semaine") || frequency.contains("week") {
                if frequency.contains("2") || frequency.contains("deux") || frequency.contains("twice") {
                    selectedFrequency = .twiceWeekly
                } else {
                    selectedFrequency = .weekly
                }
            } else if frequency.contains("mois") || frequency.contains("month") {
                selectedFrequency = .monthly
            }

            customDays = selectedFrequency.resolvedDays(customDays: customDays)
        }

        if let waterAmount = waterInfo.amount, !waterAmount.isEmpty {
            detailValue = waterAmount
        }
    }

    private func createRoutine() {
        guard !isCreating, !isCreateDisabled else { return }

        Task {
            await MainActor.run { isCreating = true }

            var calendarEventId: String? = nil

            if addToCalendar {
                let granted = await CalendarService.shared.requestAccess()

                if granted {
                    do {
                        calendarEventId = try createCalendarEvent()
                    } catch {
                        print("❌ Calendar event creation failed: \(error)")
                        await MainActor.run {
                            isCreating = false
                            errorMessage = error.localizedDescription
                            showingErrorAlert = true
                        }
                        return
                    }
                } else {
                    await MainActor.run {
                        isCreating = false
                        showingCalendarDeniedAlert = true
                    }
                    return
                }
            }

            await MainActor.run {
                saveLocalRoutine(calendarEventId: calendarEventId)
                isCreating = false
                calendarSuccessMessage = successMessage
                showingSuccessAlert = true
            }
        }
    }

    private func createCalendarEvent() throws -> String {
        switch selectedAction {
        case .watering:
            return try CalendarService.shared.createWateringEvent(
                plantName: selectedPlantName,
                frequency: selectedFrequency,
                customDays: finalDays,
                reminderTime: reminderTime,
                firstDate: firstActionDate,
                amount: detailValue,
                notes: notes
            )
        case .care:
            return try CalendarService.shared.createCareEvent(
                plantName: selectedPlantName,
                actionTitle: actionTitle,
                frequency: selectedFrequency,
                customDays: finalDays,
                reminderTime: reminderTime,
                firstDate: firstActionDate,
                detailLabel: selectedAction.detailSectionTitle,
                detail: detailValue,
                notes: notes
            )
        }
    }

    private func saveLocalRoutine(calendarEventId: String?) {
        switch selectedAction {
        case .watering:
            let routine = WateringRoutine(
                gardenId: gardenId,
                plantId: selectedPlantIdentifier,
                plantName: selectedPlantName,
                frequency: selectedFrequency,
                customDays: selectedFrequency == .custom ? customDays : nil,
                reminderTime: reminderTime,
                amount: detailValue,
                notes: notes,
                nextWateringDate: firstScheduledDate,
                calendarEventId: calendarEventId
            )

            routineStore.saveRoutine(routine)
            onRoutineSaved?(routine)
        case .care(let kind):
            let routine = PlantCareRoutine(
                gardenId: gardenId,
                plantId: selectedPlantIdentifier,
                plantName: selectedPlantName,
                kind: kind,
                customTitle: selectedAction.requiresCustomTitle ? customActionTitle : "",
                intervalDays: finalDays,
                reminderTime: reminderTime,
                detail: detailValue,
                notes: notes,
                nextCareDate: firstScheduledDate,
                calendarEventId: calendarEventId
            )

            routineStore.saveCareRoutine(routine)
            onCareRoutineSaved?(routine)
        }
    }

    private var successMessage: String {
        switch selectedAction {
        case .watering:
            return addToCalendar
                ? NSLocalizedString("ROUTINE_SUCCESS_WITH_CALENDAR", comment: "")
                : NSLocalizedString("ROUTINE_SUCCESS_MESSAGE", comment: "")
        case .care:
            return addToCalendar
                ? "Ta routine de soin a été créée et ajoutée à ton calendrier Apple."
                : "Ta routine de soin a été créée."
        }
    }
}

// MARK: - Subviews

private struct SectionHeaderLabel: View {
    let icon: String
    let title: String
    var tint: Color = Color(hex: "#38BDF8")
    @Environment(\.colorScheme) private var colorScheme

    private var titleColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tint)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(titleColor)
        }
    }
}

private struct FrequencyCard: View {
    let frequency: WateringFrequency
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var cardBackgroundColor: Color {
        if isSelected {
            return tint
        }
        return colorScheme == .dark
        ? Color(red: 0.11, green: 0.11, blue: 0.12)
        : Color(red: 0.95, green: 0.95, blue: 0.96)
    }

    private var textColor: Color {
        if isSelected {
            return .white
        }
        return colorScheme == .dark ? .white : .black
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.2) : tint.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: frequency.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isSelected ? .white : tint)
                }

                Text(frequency.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(cardBackgroundColor)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? tint : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(
                color: isSelected ? tint.opacity(0.3) : Color.clear,
                radius: 8,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

struct CreateWateringRoutineView_Previews: PreviewProvider {
    static var previews: some View {
        CreateWateringRoutineView(
            plantName: "Monstera Deliciosa",
            waterInfo: WaterInfo(
                frequency: "1 fois par semaine",
                amount: "200-300ml",
                method: "Arrosage modéré",
                humidity: "60-70%",
                signsLack: "Feuilles tombantes",
                signsExcess: "Feuilles jaunes",
                recommendedWater: "Eau filtrée"
            )
        )
        .environmentObject(ThemeManager())
    }
}
