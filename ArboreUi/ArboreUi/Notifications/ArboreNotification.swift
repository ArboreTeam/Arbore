import Foundation
import UserNotifications

enum ArboreNotificationCategory: String, Codable, CaseIterable {
    case wateringReminder
    case careReminder
    case projectCompletion
    case climateEmergency
    case marketplaceOrder
    case seasonalTip
    case unknown
}

enum ArboreNotificationAuthorizationState: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    var canScheduleNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied, .unknown:
            return false
        }
    }

    init(settings: UNNotificationSettings) {
        switch settings.authorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unknown
        }
    }
}

enum GardenNotificationTab: String, Codable, Hashable {
    case plan
    case tasks
    case purchase
}

enum NotificationRoute: Hashable {
    case home
    case catalogue
    case plantDetail(plantId: String)
    case garden(gardenId: String?, tab: GardenNotificationTab?, plantId: String?, routineId: String?)
    case watering(gardenId: String?, plantId: String?, routineId: String?)
    case marketplaceOrder(orderId: String)
    case profileNotifications

    var url: URL {
        var components = URLComponents()
        components.scheme = "arbore"

        switch self {
        case .home:
            components.host = "home"
        case .catalogue:
            components.host = "catalogue"
        case .plantDetail(let plantId):
            components.host = "plant"
            components.path = "/\(plantId)"
        case .garden(let gardenId, let tab, let plantId, let routineId):
            components.host = "garden"
            if let gardenId {
                components.path = "/\(gardenId)"
            }
            components.queryItems = Self.queryItems([
                "tab": tab?.rawValue,
                "plantId": plantId,
                "routineId": routineId
            ])
        case .watering(let gardenId, let plantId, let routineId):
            components.host = "watering"
            components.queryItems = Self.queryItems([
                "gardenId": gardenId,
                "plantId": plantId,
                "routineId": routineId
            ])
        case .marketplaceOrder(let orderId):
            components.host = "marketplace"
            components.path = "/order/\(orderId)"
        case .profileNotifications:
            components.host = "profile"
            components.path = "/notifications"
        }

        return components.url ?? URL(string: "arbore://home")!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "arbore" else { return nil }

        let host = url.host?.lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [String: String]()) { result, item in
                result[item.name] = item.value
            } ?? [:]

        switch host {
        case "home":
            self = .home
        case "catalogue", "catalog":
            self = .catalogue
        case "plant":
            guard let plantId = pathComponents.first, !plantId.isEmpty else { return nil }
            self = .plantDetail(plantId: plantId)
        case "garden", "project":
            let gardenId = pathComponents.first
            let tab = query["tab"].flatMap(GardenNotificationTab.init(rawValue:))
            self = .garden(
                gardenId: gardenId,
                tab: tab,
                plantId: query["plantId"] ?? query["plant_id"],
                routineId: query["routineId"] ?? query["routine_id"]
            )
        case "watering":
            self = .watering(
                gardenId: query["gardenId"] ?? query["garden_id"],
                plantId: query["plantId"] ?? query["plant_id"],
                routineId: query["routineId"] ?? query["routine_id"]
            )
        case "marketplace":
            guard pathComponents.first == "order",
                  let orderId = pathComponents.dropFirst().first,
                  !orderId.isEmpty else { return nil }
            self = .marketplaceOrder(orderId: orderId)
        case "profile":
            if pathComponents.first == "notifications" {
                self = .profileNotifications
            } else {
                self = .home
            }
        default:
            return nil
        }
    }

    private static func queryItems(_ values: [String: String?]) -> [URLQueryItem]? {
        let items = values.compactMap { key, value -> URLQueryItem? in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        return items.isEmpty ? nil : items
    }
}

enum ArboreNotificationSchedule {
    case calendar(DateComponents, repeats: Bool)
    case date(Date)
    case timeInterval(TimeInterval, repeats: Bool)

    var trigger: UNNotificationTrigger {
        switch self {
        case .calendar(let components, let repeats):
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        case .date(let date):
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        case .timeInterval(let interval, let repeats):
            return UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: repeats)
        }
    }
}

struct ArboreNotification {
    let id: String
    let title: String
    let body: String
    let category: ArboreNotificationCategory
    let schedule: ArboreNotificationSchedule
    let route: NotificationRoute
    var threadIdentifier: String?
    var subtitle: String?
    var badge: NSNumber?
    var sound: UNNotificationSound?
    var interruptionLevel: UNNotificationInterruptionLevel
    var relevanceScore: Double
    var imageURL: URL?
    var metadata: [String: String]

    init(
        id: String,
        title: String,
        body: String,
        category: ArboreNotificationCategory,
        schedule: ArboreNotificationSchedule,
        route: NotificationRoute,
        threadIdentifier: String? = nil,
        subtitle: String? = nil,
        badge: NSNumber? = nil,
        sound: UNNotificationSound? = .default,
        interruptionLevel: UNNotificationInterruptionLevel = .active,
        relevanceScore: Double = 0.5,
        imageURL: URL? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
        self.schedule = schedule
        self.route = route
        self.threadIdentifier = threadIdentifier
        self.subtitle = subtitle
        self.badge = badge
        self.sound = sound
        self.interruptionLevel = interruptionLevel
        self.relevanceScore = min(max(relevanceScore, 0), 1)
        self.imageURL = imageURL
        self.metadata = metadata
    }
}

enum ArboreNotificationPayloadKey {
    static let notificationId = "notification_id"
    static let category = "notification_category"
    static let route = "route"
    static let plantId = "plant_id"
    static let gardenId = "garden_id"
    static let routineId = "routine_id"
    static let orderId = "order_id"
    static let imageURL = "image_url"
}
