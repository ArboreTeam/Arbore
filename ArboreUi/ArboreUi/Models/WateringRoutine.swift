import Foundation
import SwiftUI

// MARK: - Watering Routine Model

struct WateringRoutine: Identifiable, Codable {
    let id: String
    var plantName: String
    var frequency: WateringFrequency
    var reminderTime: Date
    var amount: String
    var notes: String
    var isActive: Bool
    var nextWateringDate: Date
    var createdAt: Date
    
    init(
        id: String = UUID().uuidString,
        plantName: String,
        frequency: WateringFrequency,
        reminderTime: Date = Date(),
        amount: String = "",
        notes: String = "",
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.plantName = plantName
        self.frequency = frequency
        self.reminderTime = reminderTime
        self.amount = amount
        self.notes = notes
        self.isActive = isActive
        self.createdAt = createdAt
        self.nextWateringDate = frequency.calculateNextDate(from: Date())
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
        switch self {
        case .daily: return 1
        case .twiceWeekly: return 3
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly: return 30
        case .custom: return 7 // default
        }
    }
    
    func calculateNextDate(from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
}
