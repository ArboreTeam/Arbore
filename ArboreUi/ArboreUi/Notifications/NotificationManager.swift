import Foundation
import UIKit
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private let center: UNUserNotificationCenter
    private let planner = ArboreNotificationPlanner()

    private init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func currentAuthorizationState() async -> ArboreNotificationAuthorizationState {
        let settings = await center.notificationSettings()
        return ArboreNotificationAuthorizationState(settings: settings)
    }

    @discardableResult
    func requestAuthorization(provisional: Bool = false) async -> ArboreNotificationAuthorizationState {
        var options: UNAuthorizationOptions = [.alert, .badge, .sound]
        if provisional {
            options.insert(.provisional)
        }

        do {
            _ = try await center.requestAuthorization(options: options)
        } catch {
            print("Notification authorization request failed: \(error)")
        }

        let state = await currentAuthorizationState()
        if state.canScheduleNotifications {
            await registerForRemoteNotifications()
        }
        return state
    }

    func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    @MainActor
    func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func configureCategories() {
        let markWatered = UNNotificationAction(
            identifier: ArboreNotificationActionIdentifier.markWatered,
            title: "Arrosee",
            options: []
        )
        let deferTomorrow = UNNotificationAction(
            identifier: ArboreNotificationActionIdentifier.deferTomorrow,
            title: "Demain",
            options: []
        )
        let open = UNNotificationAction(
            identifier: ArboreNotificationActionIdentifier.open,
            title: "Ouvrir",
            options: [.foreground]
        )

        let watering = UNNotificationCategory(
            identifier: ArboreNotificationCategory.wateringReminder.rawValue,
            actions: [markWatered, deferTomorrow, open],
            intentIdentifiers: [],
            options: []
        )

        let careDone = UNNotificationAction(
            identifier: ArboreNotificationActionIdentifier.markCareDone,
            title: "Fait",
            options: []
        )
        let care = UNNotificationCategory(
            identifier: ArboreNotificationCategory.careReminder.rawValue,
            actions: [careDone, deferTomorrow, open],
            intentIdentifiers: [],
            options: []
        )

        let urgent = UNNotificationCategory(
            identifier: ArboreNotificationCategory.climateEmergency.rawValue,
            actions: [open],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([watering, care, urgent])
    }

    func schedule(_ notification: ArboreNotification) async throws {
        let state = await currentAuthorizationState()
        guard state.canScheduleNotifications else {
            throw NotificationManagerError.authorizationDenied(state)
        }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.categoryIdentifier = notification.category.rawValue
        content.userInfo = makeUserInfo(from: notification)
        content.sound = notification.sound
        content.badge = notification.badge
        content.interruptionLevel = notification.interruptionLevel
        content.relevanceScore = notification.relevanceScore

        if let subtitle = notification.subtitle {
            content.subtitle = subtitle
        }
        if let threadIdentifier = notification.threadIdentifier {
            content.threadIdentifier = threadIdentifier
        }

        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: notification.schedule.trigger
        )

        center.removePendingNotificationRequests(withIdentifiers: [notification.id])
        try await center.add(request)
    }

    func schedule(_ notifications: [ArboreNotification]) async {
        for notification in notifications {
            do {
                try await schedule(notification)
            } catch {
                print("Unable to schedule notification \(notification.id): \(error)")
            }
        }
    }

    func scheduleWateringReminder(
        for routine: WateringRoutine,
        careProfile: ArborePlantCareProfile? = nil,
        weather: ArboreLocalWeatherSnapshot? = nil
    ) async {
        guard routine.isActive else {
            cancelWateringReminder(routineId: routine.id)
            return
        }

        await schedule([
            planner.wateringReminder(
                for: routine,
                careProfile: careProfile,
                weather: weather
            )
        ])
    }

    func scheduleCareReminder(for routine: PlantCareRoutine) async {
        guard routine.isActive else {
            cancelCareReminder(routineId: routine.id)
            return
        }

        await schedule([planner.careReminder(for: routine)])
    }

    func scheduleProjectCompletionReminder(
        projectId: String,
        projectName: String,
        hasPlacedPlants: Bool
    ) async {
        let identifier = ArboreNotificationPlanner.projectCompletionIdentifier(projectId: projectId)
        guard !hasPlacedPlants else {
            cancel(ids: [identifier])
            return
        }

        await schedule([
            planner.projectCompletionReminder(
                projectId: projectId,
                projectName: projectName
            )
        ])
    }

    func cancel(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func cancelWateringReminder(routineId: String) {
        cancel(ids: [ArboreNotificationPlanner.wateringIdentifier(routineId: routineId)])
    }

    func cancelCareReminder(routineId: String) {
        cancel(ids: [ArboreNotificationPlanner.careIdentifier(routineId: routineId)])
    }

    func cancelProjectCompletionReminder(projectId: String) {
        cancel(ids: [ArboreNotificationPlanner.projectCompletionIdentifier(projectId: projectId)])
    }

    func cancelObsoleteRoutineNotifications(activeWateringRoutineIds: Set<String>, activeCareRoutineIds: Set<String>) async {
        let pending = await center.pendingNotificationRequests()
        let obsolete = pending.compactMap { request -> String? in
            if request.identifier.hasPrefix("watering.") {
                let routineId = String(request.identifier.dropFirst("watering.".count))
                return activeWateringRoutineIds.contains(routineId) ? nil : request.identifier
            }
            if request.identifier.hasPrefix("care.") {
                let routineId = String(request.identifier.dropFirst("care.".count))
                return activeCareRoutineIds.contains(routineId) ? nil : request.identifier
            }
            return nil
        }

        if !obsolete.isEmpty {
            cancel(ids: obsolete)
        }
    }

    func cancelAllArboreNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()

        let pendingIds = pending
            .filter { request in
                request.identifier.hasPrefix("watering.")
                || request.identifier.hasPrefix("care.")
                || request.identifier.hasPrefix("project-completion.")
                || request.identifier.hasPrefix("climate.")
                || request.identifier.hasPrefix("marketplace.")
            }
            .map(\.identifier)

        let deliveredIds = delivered
            .map(\.request)
            .filter { request in
                request.identifier.hasPrefix("watering.")
                || request.identifier.hasPrefix("care.")
                || request.identifier.hasPrefix("project-completion.")
                || request.identifier.hasPrefix("climate.")
                || request.identifier.hasPrefix("marketplace.")
            }
            .map(\.identifier)

        center.removePendingNotificationRequests(withIdentifiers: pendingIds)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIds)
    }

    func rescheduleAllRoutineNotifications(watering: [WateringRoutine], care: [PlantCareRoutine]) async {
        await cancelObsoleteRoutineNotifications(
            activeWateringRoutineIds: Set(watering.filter(\.isActive).map(\.id)),
            activeCareRoutineIds: Set(care.filter(\.isActive).map(\.id))
        )
        await schedule(watering.filter(\.isActive).map { planner.wateringReminder(for: $0) })
        await schedule(care.filter(\.isActive).map { planner.careReminder(for: $0) })
    }

    func handleNotificationAction(_ response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let routineId = userInfo[ArboreNotificationPayloadKey.routineId] as? String

        switch response.actionIdentifier {
        case ArboreNotificationActionIdentifier.markWatered:
            if let routineId {
                await MainActor.run {
                    WateringRoutineStore.shared.markWatered(routineId: routineId)
                }
            }
        case ArboreNotificationActionIdentifier.deferTomorrow:
            let category = userInfo[ArboreNotificationPayloadKey.category] as? String
            await MainActor.run {
                if category == ArboreNotificationCategory.careReminder.rawValue, let routineId {
                    WateringRoutineStore.shared.deferCareRoutine(routineId: routineId)
                } else if let routineId {
                    WateringRoutineStore.shared.deferWatering(routineId: routineId)
                }
            }
        case ArboreNotificationActionIdentifier.markCareDone:
            if let routineId {
                await MainActor.run {
                    WateringRoutineStore.shared.completeCareRoutine(routineId: routineId)
                }
            }
        default:
            break
        }
    }

    private func makeUserInfo(from notification: ArboreNotification) -> [AnyHashable: Any] {
        var userInfo: [String: Any] = [
            ArboreNotificationPayloadKey.notificationId: notification.id,
            ArboreNotificationPayloadKey.category: notification.category.rawValue,
            ArboreNotificationPayloadKey.route: notification.route.url.absoluteString
        ]

        if let imageURL = notification.imageURL {
            userInfo[ArboreNotificationPayloadKey.imageURL] = imageURL.absoluteString
        }

        notification.metadata.forEach { key, value in
            userInfo[key] = value
        }

        return userInfo
    }
}

enum NotificationManagerError: LocalizedError {
    case authorizationDenied(ArboreNotificationAuthorizationState)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied(let state):
            return "Notifications not authorized: \(state)"
        }
    }
}

enum ArboreNotificationActionIdentifier {
    static let open = "ARBORE_OPEN"
    static let markWatered = "ARBORE_MARK_WATERED"
    static let deferTomorrow = "ARBORE_DEFER_TOMORROW"
    static let markCareDone = "ARBORE_MARK_CARE_DONE"
}
