//
//  ArboreNotificationPlannerTests.swift
//  ArboreUiTests
//
//  Couvre la logique pure du planificateur de notifications (chantier juillet) :
//  identifiants, ajustement météo/soin de la date d'arrosage, contenu des notifs.
//

import XCTest
@testable import ArboreUi

final class ArboreNotificationPlannerTests: XCTestCase {

    private let planner = ArboreNotificationPlanner()

    // Base d'arrosage volontairement loin dans le futur pour que le clamp
    // `max(now+60s, …)` de adjustedWateringDate n'interfère pas avec le delta.
    private func farFutureBase() -> Date { Date().addingTimeInterval(30 * 86_400) }

    private func makeRoutine(
        nextWatering: Date,
        amount: String = "",
        notes: String = ""
    ) -> WateringRoutine {
        WateringRoutine(
            id: "r1",
            gardenId: "g1",
            plantId: "p1",
            plantName: "Basilic",
            frequency: .weekly,
            amount: amount,
            notes: notes,
            nextWateringDate: nextWatering
        )
    }

    private func expectedShift(from base: Date, days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: base)!
    }

    // MARK: - Identifiants

    func testIdentifierFormats() {
        XCTAssertEqual(ArboreNotificationPlanner.wateringIdentifier(routineId: "abc"), "watering.abc")
        XCTAssertEqual(ArboreNotificationPlanner.careIdentifier(routineId: "abc"), "care.abc")
        XCTAssertEqual(
            ArboreNotificationPlanner.projectCompletionIdentifier(projectId: "proj"),
            "project-completion.proj"
        )
    }

    // MARK: - adjustedWateringDate

    func testAdjustedDate_noSignals_isUnchanged() {
        let base = farFutureBase()
        let routine = makeRoutine(nextWatering: base)
        let result = planner.adjustedWateringDate(for: routine, careProfile: nil, weather: nil)
        XCTAssertEqual(result, base)
    }

    func testAdjustedDate_hotAndDry_pullsTwoDaysEarlier() {
        let base = farFutureBase()
        let routine = makeRoutine(nextWatering: base)
        let weather = ArboreLocalWeatherSnapshot(
            maximumTemperatureCelsius: 32,   // ≥ 30 → -1
            humidityPercent: 30              // < 35 → -1
        )
        let result = planner.adjustedWateringDate(for: routine, careProfile: nil, weather: weather)
        XCTAssertEqual(
            result.timeIntervalSinceReferenceDate,
            expectedShift(from: base, days: -2).timeIntervalSinceReferenceDate,
            accuracy: 1.0
        )
    }

    func testAdjustedDate_waterNeedHighVsLow() {
        let base = farFutureBase()
        let routine = makeRoutine(nextWatering: base)

        let high = ArborePlantCareProfile(speciesName: "x", waterNeed: .high)  // -1
        let low = ArborePlantCareProfile(speciesName: "x", waterNeed: .low)    // +1

        let resultHigh = planner.adjustedWateringDate(for: routine, careProfile: high, weather: nil)
        let resultLow = planner.adjustedWateringDate(for: routine, careProfile: low, weather: nil)

        XCTAssertEqual(
            resultHigh.timeIntervalSinceReferenceDate,
            expectedShift(from: base, days: -1).timeIntervalSinceReferenceDate,
            accuracy: 1.0
        )
        XCTAssertEqual(
            resultLow.timeIntervalSinceReferenceDate,
            expectedShift(from: base, days: 1).timeIntervalSinceReferenceDate,
            accuracy: 1.0
        )
    }

    func testAdjustedDate_outdoorRain_pushesOneDayLater() {
        let base = farFutureBase()
        let routine = makeRoutine(nextWatering: base)
        let weather = ArboreLocalWeatherSnapshot(
            precipitationProbability: 0.7,   // ≥ 0.65 en extérieur → +1
            isOutdoorContext: true
        )
        let result = planner.adjustedWateringDate(for: routine, careProfile: nil, weather: weather)
        XCTAssertEqual(
            result.timeIntervalSinceReferenceDate,
            expectedShift(from: base, days: 1).timeIntervalSinceReferenceDate,
            accuracy: 1.0
        )
    }

    // MARK: - Construction des notifications

    func testWateringReminder_idCategoryBodyAndMetadata() {
        let routine = makeRoutine(nextWatering: farFutureBase(), amount: "200ml")
        let notif = planner.wateringReminder(for: routine)

        XCTAssertEqual(notif.id, "watering.r1")
        XCTAssertEqual(notif.category, .wateringReminder)
        XCTAssertTrue(notif.body.contains("200ml"), "le body devrait reprendre la quantité")
        XCTAssertEqual(notif.metadata[ArboreNotificationPayloadKey.routineId], "r1")
        XCTAssertEqual(notif.metadata[ArboreNotificationPayloadKey.plantId], "p1")
        XCTAssertEqual(notif.metadata[ArboreNotificationPayloadKey.gardenId], "g1")
    }

    func testWateringReminder_dropsEmptyMetadata() {
        // Routine sans plantId/gardenId → ces clés ne doivent pas apparaître.
        let routine = WateringRoutine(
            id: "solo",
            plantName: "Menthe",
            frequency: .weekly,
            nextWateringDate: farFutureBase()
        )
        let notif = planner.wateringReminder(for: routine)
        XCTAssertNil(notif.metadata[ArboreNotificationPayloadKey.plantId])
        XCTAssertNil(notif.metadata[ArboreNotificationPayloadKey.gardenId])
        XCTAssertEqual(notif.metadata[ArboreNotificationPayloadKey.routineId], "solo")
    }

    func testCareReminder_idCategoryAndFallbackBody() {
        let care = PlantCareRoutine(
            id: "c1",
            gardenId: "g1",
            plantId: "p1",
            plantName: "Ficus",
            kind: .fertilize
        )
        let notif = planner.careReminder(for: care)

        XCTAssertEqual(notif.id, "care.c1")
        XCTAssertEqual(notif.category, .careReminder)
        // detail et notes vides → body de repli.
        XCTAssertTrue(notif.body.contains("Ouvrez Arbore"))
    }

    func testProjectCompletionReminder_idAndCategory() {
        let notif = planner.projectCompletionReminder(projectId: "proj42", projectName: "Balcon")
        XCTAssertEqual(notif.id, "project-completion.proj42")
        XCTAssertEqual(notif.category, .projectCompletion)
        XCTAssertTrue(notif.title.contains("Balcon"))
    }
}
