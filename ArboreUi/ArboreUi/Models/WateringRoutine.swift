import Foundation
import SwiftUI

// MARK: - Watering Routine Model

struct WateringRoutine: Identifiable, Codable {
    var id: String
    var gardenId: String?
    var plantId: String?
    var plantName: String
    var frequency: WateringFrequency
    var customDays: Int?
    var reminderTime: Date
    var amount: String
    var notes: String
    var isActive: Bool
    var nextWateringDate: Date
    var createdAt: Date
    var lastWateredAt: Date?
    var lastSkippedAt: Date?
    var calendarEventId: String?
    
    init(
        id: String = UUID().uuidString,
        gardenId: String? = nil,
        plantId: String? = nil,
        plantName: String,
        frequency: WateringFrequency,
        customDays: Int? = nil,
        reminderTime: Date = Date(),
        amount: String = "",
        notes: String = "",
        isActive: Bool = true,
        createdAt: Date = Date(),
        nextWateringDate: Date? = nil,
        lastWateredAt: Date? = nil,
        lastSkippedAt: Date? = nil,
        calendarEventId: String? = nil
    ) {
        self.id = id
        self.gardenId = gardenId
        self.plantId = plantId
        self.plantName = plantName
        self.frequency = frequency
        self.customDays = customDays
        self.reminderTime = reminderTime
        self.amount = amount
        self.notes = notes
        self.isActive = isActive
        self.createdAt = createdAt
        self.nextWateringDate = nextWateringDate ?? Self.nextDate(
            after: Date(),
            frequency: frequency,
            customDays: customDays,
            reminderTime: reminderTime
        )
        self.lastWateredAt = lastWateredAt
        self.lastSkippedAt = lastSkippedAt
        self.calendarEventId = calendarEventId
    }

    var intervalDays: Int {
        frequency.resolvedDays(customDays: customDays)
    }

    var frequencySummary: String {
        if frequency == .custom, let customDays {
            return L10n.f("ROUTINE_FREQUENCY_EVERY_N_DAYS", customDays)
        }
        return frequency.displayName
    }

    mutating func markWatered(on date: Date = Date()) {
        lastWateredAt = date
        lastSkippedAt = nil
        nextWateringDate = Self.nextDate(
            after: date,
            frequency: frequency,
            customDays: customDays,
            reminderTime: reminderTime
        )
    }

    mutating func deferUntilTomorrow(from date: Date = Date()) {
        lastSkippedAt = date
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        nextWateringDate = Self.mergingDate(tomorrow, withTimeFrom: reminderTime)
    }

    static func nextDate(
        after date: Date,
        frequency: WateringFrequency,
        customDays: Int?,
        reminderTime: Date
    ) -> Date {
        let interval = frequency.resolvedDays(customDays: customDays)
        let nextDay = Calendar.current.date(byAdding: .day, value: interval, to: date) ?? date
        return mergingDate(nextDay, withTimeFrom: reminderTime)
    }

    private static func mergingDate(_ date: Date, withTimeFrom time: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: timeComponents.hour ?? 9,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: date
        ) ?? date
    }
}

struct GardenCareAction: Identifiable, Codable {
    enum ActionType: String, Codable {
        case watered
        case skipped
        case routineCreated
        case careCompleted
        case careSkipped
        case careRoutineCreated
    }

    var id: String
    var gardenId: String?
    var plantId: String?
    var plantName: String
    var routineId: String?
    var type: ActionType
    var careKind: GardenCareKind?
    var title: String?
    var date: Date
    var note: String?

    init(
        id: String = UUID().uuidString,
        gardenId: String? = nil,
        plantId: String? = nil,
        plantName: String,
        routineId: String? = nil,
        type: ActionType,
        careKind: GardenCareKind? = nil,
        title: String? = nil,
        date: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.gardenId = gardenId
        self.plantId = plantId
        self.plantName = plantName
        self.routineId = routineId
        self.type = type
        self.careKind = careKind
        self.title = title
        self.date = date
        self.note = note
    }
}

enum GardenCareKind: String, Codable, CaseIterable {
    case pruneLeaves
    case cleanLeaves
    case fertilize
    case repot
    case pestCheck
    case rotatePot
    case soilCheck
    case custom

    var displayName: String {
        switch self {
        case .pruneLeaves: return L10n.t("CARE_KIND_PRUNE_LEAVES")
        case .cleanLeaves: return L10n.t("CARE_KIND_CLEAN_LEAVES")
        case .fertilize: return L10n.t("CARE_KIND_FERTILIZE")
        case .repot: return L10n.t("CARE_KIND_REPOT")
        case .pestCheck: return L10n.t("CARE_KIND_PEST_CHECK")
        case .rotatePot: return L10n.t("CARE_KIND_ROTATE_POT")
        case .soilCheck: return L10n.t("CARE_KIND_SOIL_CHECK")
        case .custom: return L10n.t("CARE_KIND_CUSTOM")
        }
    }

    var completionLabel: String {
        switch self {
        case .pruneLeaves: return L10n.t("CARE_KIND_PRUNE_LEAVES_DONE")
        case .cleanLeaves: return L10n.t("CARE_KIND_CLEAN_LEAVES_DONE")
        case .fertilize: return L10n.t("CARE_KIND_FERTILIZE_DONE")
        case .repot: return L10n.t("CARE_KIND_REPOT_DONE")
        case .pestCheck: return L10n.t("CARE_KIND_PEST_CHECK_DONE")
        case .rotatePot: return L10n.t("CARE_KIND_ROTATE_POT_DONE")
        case .soilCheck: return L10n.t("CARE_KIND_SOIL_CHECK_DONE")
        case .custom: return L10n.t("CARE_KIND_CUSTOM_DONE")
        }
    }

    var icon: String {
        switch self {
        case .pruneLeaves: return "scissors"
        case .cleanLeaves: return "sparkles"
        case .fertilize: return "leaf.arrow.circlepath"
        case .repot: return "shippingbox.fill"
        case .pestCheck: return "ladybug.fill"
        case .rotatePot: return "arrow.triangle.2.circlepath"
        case .soilCheck: return "mountain.2.fill"
        case .custom: return "checklist"
        }
    }

    var tintHex: String {
        switch self {
        case .pruneLeaves: return "#D8A85B"
        case .cleanLeaves: return "#2F6B46"
        case .fertilize: return "#5B8C46"
        case .repot: return "#8B6F47"
        case .pestCheck: return "#D98B4A"
        case .rotatePot: return "#7A7F43"
        case .soilCheck: return "#8F6A3D"
        case .custom: return "#607466"
        }
    }

    var defaultIntervalDays: Int {
        // Surcharge distante (config /config, issue #236) si disponible,
        // sinon valeur de repli codée en dur.
        if let remote = RemoteConfigService.shared.careIntervalDays(forKind: rawValue) {
            return remote
        }
        switch self {
        case .pruneLeaves: return 30
        case .cleanLeaves: return 14
        case .fertilize: return 21
        case .repot: return 180
        case .pestCheck: return 14
        case .rotatePot: return 7
        case .soilCheck: return 7
        case .custom: return 14
        }
    }
}

struct PlantCareRoutine: Identifiable, Codable {
    var id: String
    var gardenId: String?
    var plantId: String?
    var plantName: String
    var kind: GardenCareKind
    var customTitle: String
    var intervalDays: Int
    var reminderTime: Date
    var detail: String?
    var notes: String
    var isActive: Bool
    var nextCareDate: Date
    var createdAt: Date
    var lastCompletedAt: Date?
    var lastSkippedAt: Date?
    var calendarEventId: String?

    init(
        id: String = UUID().uuidString,
        gardenId: String? = nil,
        plantId: String? = nil,
        plantName: String,
        kind: GardenCareKind,
        customTitle: String = "",
        intervalDays: Int? = nil,
        reminderTime: Date = Date(),
        detail: String = "",
        notes: String = "",
        isActive: Bool = true,
        nextCareDate: Date? = nil,
        createdAt: Date = Date(),
        lastCompletedAt: Date? = nil,
        lastSkippedAt: Date? = nil,
        calendarEventId: String? = nil
    ) {
        self.id = id
        self.gardenId = gardenId
        self.plantId = plantId
        self.plantName = plantName
        self.kind = kind
        self.customTitle = customTitle
        self.intervalDays = max(1, intervalDays ?? kind.defaultIntervalDays)
        self.reminderTime = reminderTime
        self.detail = detail
        self.notes = notes
        self.isActive = isActive
        self.nextCareDate = nextCareDate ?? Self.nextDate(
            after: Date(),
            intervalDays: max(1, intervalDays ?? kind.defaultIntervalDays),
            reminderTime: reminderTime
        )
        self.createdAt = createdAt
        self.lastCompletedAt = lastCompletedAt
        self.lastSkippedAt = lastSkippedAt
        self.calendarEventId = calendarEventId
    }

    var title: String {
        if kind == .custom {
            let trimmed = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? kind.displayName : trimmed
        }
        return kind.displayName
    }

    var frequencySummary: String {
        if intervalDays == 1 { return L10n.t("ROUTINE_FREQUENCY_DAILY") }
        return L10n.f("ROUTINE_FREQUENCY_EVERY_N_DAYS", intervalDays)
    }

    mutating func markCompleted(on date: Date = Date()) {
        lastCompletedAt = date
        lastSkippedAt = nil
        nextCareDate = Self.nextDate(
            after: date,
            intervalDays: intervalDays,
            reminderTime: reminderTime
        )
    }

    mutating func deferUntilTomorrow(from date: Date = Date()) {
        lastSkippedAt = date
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        nextCareDate = Self.mergingDate(tomorrow, withTimeFrom: reminderTime)
    }

    static func nextDate(after date: Date, intervalDays: Int, reminderTime: Date) -> Date {
        let nextDay = Calendar.current.date(byAdding: .day, value: max(1, intervalDays), to: date) ?? date
        return mergingDate(nextDay, withTimeFrom: reminderTime)
    }

    static func mergingDate(_ date: Date, withTimeFrom time: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: timeComponents.hour ?? 9,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: date
        ) ?? date
    }
}

final class WateringRoutineStore: ObservableObject {
    static let shared = WateringRoutineStore()

    @Published private(set) var routines: [WateringRoutine] = []
    @Published private(set) var careRoutines: [PlantCareRoutine] = []
    @Published private(set) var actions: [GardenCareAction] = []

    private let defaults: UserDefaults
    private let routinesKey = "wateringRoutines"
    private let careRoutinesKey = "plantCareRoutines"
    private let actionsKey = "gardenCareActions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
        rescheduleRoutineNotifications()
    }

    func reload() {
        routines = decode([WateringRoutine].self, forKey: routinesKey) ?? []
        careRoutines = decode([PlantCareRoutine].self, forKey: careRoutinesKey) ?? []
        actions = decode([GardenCareAction].self, forKey: actionsKey) ?? []
        actions.sort { $0.date > $1.date }
    }

    func saveRoutine(_ routine: WateringRoutine) {
        if let index = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[index] = routine
        } else {
            routines.append(routine)
            appendAction(
                GardenCareAction(
                    gardenId: routine.gardenId,
                    plantId: routine.plantId,
                    plantName: routine.plantName,
                    routineId: routine.id,
                    type: .routineCreated
                )
            )
        }
        persistRoutines()
        syncWateringNotification(for: routine)
    }

    func markWatered(routineId: String, on date: Date = Date()) {
        guard let index = routines.firstIndex(where: { $0.id == routineId }) else { return }
        routines[index].markWatered(on: date)
        appendAction(
            GardenCareAction(
                gardenId: routines[index].gardenId,
                plantId: routines[index].plantId,
                plantName: routines[index].plantName,
                routineId: routines[index].id,
                type: .watered,
                date: date
            )
        )
        persistRoutines()
        syncWateringNotification(for: routines[index])
    }

    func saveCareRoutine(_ routine: PlantCareRoutine) {
        if let index = careRoutines.firstIndex(where: { $0.id == routine.id }) {
            careRoutines[index] = routine
        } else {
            careRoutines.append(routine)
            appendAction(
                GardenCareAction(
                    gardenId: routine.gardenId,
                    plantId: routine.plantId,
                    plantName: routine.plantName,
                    routineId: routine.id,
                    type: .careRoutineCreated,
                    careKind: routine.kind,
                    title: routine.title
                )
            )
        }
        persistCareRoutines()
        syncCareNotification(for: routine)
    }

    func completeCareRoutine(routineId: String, on date: Date = Date()) {
        guard let index = careRoutines.firstIndex(where: { $0.id == routineId }) else { return }
        careRoutines[index].markCompleted(on: date)
        appendAction(
            GardenCareAction(
                gardenId: careRoutines[index].gardenId,
                plantId: careRoutines[index].plantId,
                plantName: careRoutines[index].plantName,
                routineId: careRoutines[index].id,
                type: .careCompleted,
                careKind: careRoutines[index].kind,
                title: careRoutines[index].title,
                date: date
            )
        )
        persistCareRoutines()
        syncCareNotification(for: careRoutines[index])
    }

    func deferCareRoutine(routineId: String, on date: Date = Date()) {
        guard let index = careRoutines.firstIndex(where: { $0.id == routineId }) else { return }
        careRoutines[index].deferUntilTomorrow(from: date)
        appendAction(
            GardenCareAction(
                gardenId: careRoutines[index].gardenId,
                plantId: careRoutines[index].plantId,
                plantName: careRoutines[index].plantName,
                routineId: careRoutines[index].id,
                type: .careSkipped,
                careKind: careRoutines[index].kind,
                title: careRoutines[index].title,
                date: date
            )
        )
        persistCareRoutines()
        syncCareNotification(for: careRoutines[index])
    }

    func deferWatering(routineId: String, on date: Date = Date()) {
        guard let index = routines.firstIndex(where: { $0.id == routineId }) else { return }
        routines[index].deferUntilTomorrow(from: date)
        appendAction(
            GardenCareAction(
                gardenId: routines[index].gardenId,
                plantId: routines[index].plantId,
                plantName: routines[index].plantName,
                routineId: routines[index].id,
                type: .skipped,
                date: date
            )
        )
        persistRoutines()
        syncWateringNotification(for: routines[index])
    }

    private func appendAction(_ action: GardenCareAction) {
        actions.insert(action, at: 0)
        if actions.count > 120 {
            actions = Array(actions.prefix(120))
        }
        persistActions()
    }

    private func persistRoutines() {
        persist(routines, forKey: routinesKey)
    }

    private func persistCareRoutines() {
        persist(careRoutines, forKey: careRoutinesKey)
    }

    private func persistActions() {
        persist(actions, forKey: actionsKey)
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func syncWateringNotification(for routine: WateringRoutine) {
        Task {
            await NotificationManager.shared.scheduleWateringReminder(for: routine)
        }
    }

    private func syncCareNotification(for routine: PlantCareRoutine) {
        Task {
            await NotificationManager.shared.scheduleCareReminder(for: routine)
        }
    }

    private func rescheduleRoutineNotifications() {
        let watering = routines
        let care = careRoutines
        Task {
            await NotificationManager.shared.rescheduleAllRoutineNotifications(watering: watering, care: care)
        }
    }
}

enum WateringFrequency: String, Codable, CaseIterable {
    case daily = "daily"
    case twiceWeekly = "twiceWeekly"
    case weekly = "weekly"
    case biweekly = "biweekly"
    case monthly = "monthly"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .daily:
            return NSLocalizedString("ROUTINE_FREQUENCY_DAILY", comment: "")
        case .twiceWeekly:
            return NSLocalizedString("ROUTINE_FREQUENCY_TWICE_WEEKLY", comment: "")
        case .weekly:
            return NSLocalizedString("ROUTINE_FREQUENCY_WEEKLY", comment: "")
        case .biweekly:
            return NSLocalizedString("ROUTINE_FREQUENCY_BIWEEKLY", comment: "")
        case .monthly:
            return NSLocalizedString("ROUTINE_FREQUENCY_MONTHLY", comment: "")
        case .custom:
            return NSLocalizedString("ROUTINE_FREQUENCY_CUSTOM", comment: "")
        }
    }
    
    var icon: String {
        switch self {
        case .daily: return "sun.max.fill"
        case .twiceWeekly: return "calendar.badge.clock"
        case .weekly: return "calendar"
        case .biweekly: return "calendar.badge.plus"
        case .monthly: return "calendar.circle"
        case .custom: return "slider.horizontal.3"
        }
    }
    
    var days: Int {
        // Surcharge distante (config /config, issue #236) si disponible,
        // sinon valeur de repli codée en dur.
        if let remote = RemoteConfigService.shared.wateringDays(forFrequency: rawValue) {
            return remote
        }
        switch self {
        case .daily: return 1
        case .twiceWeekly: return 3
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly: return 30
        case .custom: return 7 // default
        }
    }

    func resolvedDays(customDays: Int? = nil) -> Int {
        if self == .custom {
            return max(1, customDays ?? days)
        }
        return days
    }
    
    func calculateNextDate(from date: Date, customDays: Int? = nil) -> Date {
        Calendar.current.date(byAdding: .day, value: resolvedDays(customDays: customDays), to: date) ?? date
    }
}
