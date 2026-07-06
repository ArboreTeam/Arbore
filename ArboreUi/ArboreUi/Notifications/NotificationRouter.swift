import Foundation
import SwiftUI
import UserNotifications

struct ArboreInAppNotification: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let route: NotificationRoute
    let category: ArboreNotificationCategory
}

@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()

    @Published private(set) var pendingRoute: NotificationRoute?
    @Published var inAppNotification: ArboreInAppNotification?

    private init() {}

    func handle(url: URL) {
        guard let route = NotificationRoute(url: url) else { return }
        routeTo(route)
    }

    func handle(userInfo: [AnyHashable: Any]) {
        routeTo(route(from: userInfo))
    }

    func handle(response: UNNotificationResponse) {
        handle(userInfo: response.notification.request.content.userInfo)
    }

    func presentInAppNotification(from notification: UNNotification) {
        let content = notification.request.content
        let userInfo = content.userInfo
        let route = route(from: userInfo)
        let categoryRaw = userInfo[ArboreNotificationPayloadKey.category] as? String
        let category = categoryRaw.flatMap(ArboreNotificationCategory.init(rawValue:)) ?? .unknown

        inAppNotification = ArboreInAppNotification(
            id: notification.request.identifier,
            title: content.title,
            body: content.body,
            route: route,
            category: category
        )
    }

    func openInAppNotification(_ notification: ArboreInAppNotification) {
        inAppNotification = nil
        routeTo(notification.route)
    }

    func consumeRoute() {
        pendingRoute = nil
    }

    private func routeTo(_ route: NotificationRoute) {
        pendingRoute = route
    }

    private func route(from userInfo: [AnyHashable: Any]) -> NotificationRoute {
        if let routeString = userInfo[ArboreNotificationPayloadKey.route] as? String,
           let url = URL(string: routeString),
           let route = NotificationRoute(url: url) {
            return route
        }

        let categoryRaw = userInfo[ArboreNotificationPayloadKey.category] as? String
        let category = categoryRaw.flatMap(ArboreNotificationCategory.init(rawValue:)) ?? .unknown
        let gardenId = userInfo[ArboreNotificationPayloadKey.gardenId] as? String
        let plantId = userInfo[ArboreNotificationPayloadKey.plantId] as? String
        let routineId = userInfo[ArboreNotificationPayloadKey.routineId] as? String
        let orderId = userInfo[ArboreNotificationPayloadKey.orderId] as? String

        switch category {
        case .wateringReminder:
            return .watering(gardenId: gardenId, plantId: plantId, routineId: routineId)
        case .careReminder, .climateEmergency:
            return .garden(gardenId: gardenId, tab: .tasks, plantId: plantId, routineId: routineId)
        case .projectCompletion:
            return .garden(gardenId: gardenId, tab: .plan, plantId: plantId, routineId: routineId)
        case .marketplaceOrder:
            if let orderId, !orderId.isEmpty {
                return .marketplaceOrder(orderId: orderId)
            }
            return .garden(gardenId: gardenId, tab: .purchase, plantId: nil, routineId: nil)
        case .seasonalTip:
            return .catalogue
        case .unknown:
            return .home
        }
    }
}

extension NotificationRoute {
    var targetTab: TabSelection {
        switch self {
        case .home:
            return .home
        case .catalogue, .plantDetail:
            return .explore
        case .garden, .watering, .marketplaceOrder:
            return .garden
        case .profileNotifications:
            return .profile
        }
    }
}
