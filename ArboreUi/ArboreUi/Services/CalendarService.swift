import EventKit
import UIKit

// MARK: - CalendarService

/// Service singleton pour intégrer les routines d'arrosage avec Apple Calendar via EventKit.
/// Crée un calendrier dédié « Arbore 🌱 » et y ajoute des événements récurrents.
final class CalendarService {

    static let shared = CalendarService()

    private let eventStore = EKEventStore()
    private let calendarTitle = "Arbore 🌱"

    private init() {}

    // MARK: - Authorization

    /// État actuel de l'autorisation (sans la demander).
    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Demande l'accès complet aux événements du calendrier.
    /// - Returns: `true` si l'accès est accordé.
    func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                print("❌ CalendarService: requestFullAccessToEvents error — \(error)")
                return false
            }
        } else {
            // iOS 16 fallback
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error {
                        print("❌ CalendarService: requestAccess error — \(error)")
                    }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Arbore Calendar

    /// Retrouve ou crée le calendrier dédié « Arbore 🌱 ».
    private func getOrCreateArboreCalendar() throws -> EKCalendar {
        // 1. Cherche un calendrier existant portant notre titre
        if let existing = eventStore.calendars(for: .event)
            .first(where: { $0.title == calendarTitle }) {
            return existing
        }

        // 2. Sinon, en crée un nouveau
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = calendarTitle

        // Utilise la couleur bleue signature Arbore (#38BDF8)
        calendar.cgColor = UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0).cgColor

        // Source — préférer iCloud, sinon local
        if let iCloudSource = eventStore.sources
            .first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }) {
            calendar.source = iCloudSource
        } else if let localSource = eventStore.sources
            .first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else if let defaultSource = eventStore.defaultCalendarForNewEvents?.source {
            calendar.source = defaultSource
        } else {
            throw CalendarServiceError.noCalendarSource
        }

        try eventStore.saveCalendar(calendar, commit: true)
        print("✅ CalendarService: Calendrier « \(calendarTitle) » créé")
        return calendar
    }

    // MARK: - Create Watering Event

    /// Crée un événement récurrent dans Apple Calendar.
    /// - Parameters:
    ///   - plantName: Nom de la plante
    ///   - frequency: Fréquence d'arrosage
    ///   - customDays: Nombre de jours personnalisés (utilisé uniquement si `frequency == .custom`)
    ///   - reminderTime: Heure du rappel
    ///   - amount: Quantité d'eau (texte libre)
    ///   - notes: Notes personnelles
    /// - Returns: L'identifiant de l'événement (`eventIdentifier`) pour stockage local.
    func createWateringEvent(
        plantName: String,
        frequency: WateringFrequency,
        customDays: Int,
        reminderTime: Date,
        amount: String,
        notes: String
    ) throws -> String {

        let calendar = try getOrCreateArboreCalendar()

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar

        // Titre
        event.title = "💧 Arroser \(plantName)"

        // Date de début — aujourd'hui à l'heure choisie
        let cal = Calendar.current
        let timeComponents = cal.dateComponents([.hour, .minute], from: reminderTime)
        var startComponents = cal.dateComponents([.year, .month, .day], from: Date())
        startComponents.hour = timeComponents.hour
        startComponents.minute = timeComponents.minute

        guard let startDate = cal.date(from: startComponents) else {
            throw CalendarServiceError.invalidDate
        }

        event.startDate = startDate
        // Événement de 30 minutes par défaut
        event.endDate = cal.date(byAdding: .minute, value: 30, to: startDate)

        // Notes
        var eventNotes: [String] = []
        if !amount.isEmpty {
            eventNotes.append("💧 Quantité : \(amount)")
        }
        if !notes.isEmpty {
            eventNotes.append("📝 \(notes)")
        }
        eventNotes.append("\n🌱 Créé par Arbore")
        event.notes = eventNotes.joined(separator: "\n")

        // Alarme 15 min avant
        event.addAlarm(EKAlarm(relativeOffset: -15 * 60))

        // Récurrence
        let recurrenceRule = buildRecurrenceRule(frequency: frequency, customDays: customDays)
        event.addRecurrenceRule(recurrenceRule)

        // Sauvegarde
        try eventStore.save(event, span: .futureEvents, commit: true)
        print("✅ CalendarService: Événement créé — \(event.title ?? "") (id: \(event.eventIdentifier ?? "?"))")

        return event.eventIdentifier
    }

    // MARK: - Remove Event

    /// Supprime un événement récurrent (et ses futures occurrences) du calendrier.
    func removeWateringEvent(eventId: String) throws {
        guard let event = eventStore.event(withIdentifier: eventId) else {
            print("⚠️ CalendarService: Événement introuvable — \(eventId)")
            return
        }
        try eventStore.remove(event, span: .futureEvents, commit: true)
        print("✅ CalendarService: Événement supprimé — \(eventId)")
    }

    // MARK: - Recurrence Helpers

    private func buildRecurrenceRule(frequency: WateringFrequency, customDays: Int) -> EKRecurrenceRule {
        switch frequency {
        case .daily:
            return EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: 1,
                end: nil
            )
        case .twiceWeekly:
            // Lundi et Jeudi (2× par semaine en alternance raisonnable)
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: [
                    EKRecurrenceDayOfWeek(.monday),
                    EKRecurrenceDayOfWeek(.thursday)
                ],
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )
        case .weekly:
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                end: nil
            )
        case .biweekly:
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 2,
                end: nil
            )
        case .monthly:
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: 1,
                end: nil
            )
        case .custom:
            return EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: max(1, customDays),
                end: nil
            )
        }
    }
}

// MARK: - Errors

enum CalendarServiceError: LocalizedError {
    case noCalendarSource
    case invalidDate
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .noCalendarSource:
            return "Aucune source de calendrier disponible sur cet appareil."
        case .invalidDate:
            return "Impossible de calculer la date de l'événement."
        case .accessDenied:
            return "L'accès au calendrier a été refusé."
        }
    }
}
