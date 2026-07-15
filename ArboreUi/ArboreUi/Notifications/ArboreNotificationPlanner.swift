import Foundation

struct ArboreLocalWeatherSnapshot: Codable, Equatable {
    var minimumTemperatureCelsius: Double?
    var maximumTemperatureCelsius: Double?
    var humidityPercent: Double?
    var precipitationProbability: Double?
    var isOutdoorContext: Bool
    var observedAt: Date

    init(
        minimumTemperatureCelsius: Double? = nil,
        maximumTemperatureCelsius: Double? = nil,
        humidityPercent: Double? = nil,
        precipitationProbability: Double? = nil,
        isOutdoorContext: Bool = false,
        observedAt: Date = Date()
    ) {
        self.minimumTemperatureCelsius = minimumTemperatureCelsius
        self.maximumTemperatureCelsius = maximumTemperatureCelsius
        self.humidityPercent = humidityPercent
        self.precipitationProbability = precipitationProbability
        self.isOutdoorContext = isOutdoorContext
        self.observedAt = observedAt
    }
}

struct ArborePlantCareProfile: Codable, Equatable {
    enum WaterNeed: String, Codable {
        case low
        case moderate
        case high
    }

    var plantId: String?
    var speciesName: String
    var waterNeed: WaterNeed
    var preferredIntervalDays: Int?
    var isFrostSensitive: Bool

    init(
        plantId: String? = nil,
        speciesName: String,
        waterNeed: WaterNeed = .moderate,
        preferredIntervalDays: Int? = nil,
        isFrostSensitive: Bool = false
    ) {
        self.plantId = plantId
        self.speciesName = speciesName
        self.waterNeed = waterNeed
        self.preferredIntervalDays = preferredIntervalDays
        self.isFrostSensitive = isFrostSensitive
    }
}

struct ArboreNotificationPlanner {
    func wateringReminder(
        for routine: WateringRoutine,
        careProfile: ArborePlantCareProfile? = nil,
        weather: ArboreLocalWeatherSnapshot? = nil
    ) -> ArboreNotification {
        let date = adjustedWateringDate(for: routine, careProfile: careProfile, weather: weather)
        let route = NotificationRoute.watering(
            gardenId: routine.gardenId,
            plantId: routine.plantId,
            routineId: routine.id
        )

        return ArboreNotification(
            id: Self.wateringIdentifier(routineId: routine.id),
            title: "Il est temps d'arroser \(routine.plantName)",
            body: wateringBody(for: routine, careProfile: careProfile, weather: weather),
            category: .wateringReminder,
            schedule: .date(date),
            route: route,
            threadIdentifier: "watering.\(routine.gardenId ?? "global")",
            interruptionLevel: .active,
            relevanceScore: 0.78,
            metadata: [
                ArboreNotificationPayloadKey.routineId: routine.id,
                ArboreNotificationPayloadKey.plantId: routine.plantId ?? "",
                ArboreNotificationPayloadKey.gardenId: routine.gardenId ?? ""
            ].filter { !$0.value.isEmpty }
        )
    }

    func careReminder(for routine: PlantCareRoutine) -> ArboreNotification {
        let route = NotificationRoute.garden(
            gardenId: routine.gardenId,
            tab: .tasks,
            plantId: routine.plantId,
            routineId: routine.id
        )

        return ArboreNotification(
            id: Self.careIdentifier(routineId: routine.id),
            title: "\(routine.title) pour \(routine.plantName)",
            body: careBody(for: routine),
            category: .careReminder,
            schedule: .date(routine.nextCareDate),
            route: route,
            threadIdentifier: "care.\(routine.gardenId ?? "global")",
            interruptionLevel: .active,
            relevanceScore: 0.72,
            metadata: [
                ArboreNotificationPayloadKey.routineId: routine.id,
                ArboreNotificationPayloadKey.plantId: routine.plantId ?? "",
                ArboreNotificationPayloadKey.gardenId: routine.gardenId ?? ""
            ].filter { !$0.value.isEmpty }
        )
    }

    func projectCompletionReminder(projectId: String, projectName: String) -> ArboreNotification {
        ArboreNotification(
            id: Self.projectCompletionIdentifier(projectId: projectId),
            title: "Votre jardin \(projectName) attend ses plantes",
            body: "Reprenez le projet et placez vos premieres plantes en realite augmentee.",
            category: .projectCompletion,
            schedule: .timeInterval(72 * 60 * 60, repeats: false),
            route: .garden(gardenId: projectId, tab: .plan, plantId: nil, routineId: nil),
            threadIdentifier: "project-completion",
            interruptionLevel: .passive,
            relevanceScore: 0.42,
            metadata: [
                ArboreNotificationPayloadKey.gardenId: projectId
            ]
        )
    }

    func climateEmergency(
        id: String,
        title: String,
        body: String,
        gardenId: String?,
        imageURL: URL?
    ) -> ArboreNotification {
        ArboreNotification(
            id: "climate.\(id)",
            title: title,
            body: body,
            category: .climateEmergency,
            schedule: .timeInterval(1, repeats: false),
            route: .garden(gardenId: gardenId, tab: .tasks, plantId: nil, routineId: nil),
            threadIdentifier: "climate",
            interruptionLevel: .timeSensitive,
            relevanceScore: 0.98,
            imageURL: imageURL,
            metadata: [
                ArboreNotificationPayloadKey.gardenId: gardenId ?? ""
            ].filter { !$0.value.isEmpty }
        )
    }

    func adjustedWateringDate(
        for routine: WateringRoutine,
        careProfile: ArborePlantCareProfile?,
        weather: ArboreLocalWeatherSnapshot?
    ) -> Date {
        var dayDelta = 0

        if let preferredIntervalDays = careProfile?.preferredIntervalDays {
            let currentInterval = max(1, routine.intervalDays)
            dayDelta += min(2, max(-2, preferredIntervalDays - currentInterval))
        }

        switch careProfile?.waterNeed {
        case .high:
            dayDelta -= 1
        case .low:
            dayDelta += 1
        case .moderate, .none:
            break
        }

        if let weather {
            if let maximum = weather.maximumTemperatureCelsius, maximum >= 30 {
                dayDelta -= 1
            }
            if let humidity = weather.humidityPercent, humidity < 35 {
                dayDelta -= 1
            }
            if weather.isOutdoorContext,
               let precipitation = weather.precipitationProbability,
               precipitation >= 0.65 {
                dayDelta += 1
            }
            if weather.isOutdoorContext,
               careProfile?.isFrostSensitive == true,
               let minimum = weather.minimumTemperatureCelsius,
               minimum <= 1 {
                dayDelta += 1
            }
        }

        guard dayDelta != 0,
              let adjusted = Calendar.current.date(byAdding: .day, value: dayDelta, to: routine.nextWateringDate) else {
            return routine.nextWateringDate
        }

        return max(Date().addingTimeInterval(60), adjusted)
    }

    static func wateringIdentifier(routineId: String) -> String {
        "watering.\(routineId)"
    }

    static func careIdentifier(routineId: String) -> String {
        "care.\(routineId)"
    }

    static func projectCompletionIdentifier(projectId: String) -> String {
        "project-completion.\(projectId)"
    }

    private func wateringBody(
        for routine: WateringRoutine,
        careProfile: ArborePlantCareProfile?,
        weather: ArboreLocalWeatherSnapshot?
    ) -> String {
        var parts: [String] = []

        if !routine.amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(routine.amount)
        }

        if let maximum = weather?.maximumTemperatureCelsius, maximum >= 30 {
            parts.append("Chaleur prevue: controlez l'humidite du substrat.")
        } else if let humidity = weather?.humidityPercent, humidity < 35 {
            parts.append("Air sec detecte: surveillez les feuilles.")
        } else if careProfile?.waterNeed == .high {
            parts.append("Cette espece aime garder un substrat legerement humide.")
        } else {
            parts.append("Verifiez le substrat avant d'arroser.")
        }

        if !routine.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(routine.notes)
        }

        return parts.joined(separator: " ")
    }

    private func careBody(for routine: PlantCareRoutine) -> String {
        let detail = (routine.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = routine.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if !detail.isEmpty && !notes.isEmpty {
            return "\(detail). \(notes)"
        }
        if !detail.isEmpty {
            return detail
        }
        if !notes.isEmpty {
            return notes
        }
        return "Ouvrez Arbore pour valider ou reporter ce soin."
    }
}
