import SwiftUI

// Removed @main to avoid duplicate App entry in the same module; use this struct
// by moving it into a separate target if you need a standalone app for the measure
// sample.
struct measure_appApp: App {
    var body: some Scene {
        WindowGroup {
            GardenMeasureView()
        }
    }
}
