import Foundation
import UIKit

@MainActor
final class PlantThumbnailGenerator: ObservableObject {

    static let shared = PlantThumbnailGenerator()

    private let renderer = PlantThumbnailRenderer()
    private var queue: [Plant] = []
    private var isRendering = false
    private var queuedPlantIDs = Set<String>()
    private var pendingCallbacks: [String: [(UIImage?) -> Void]] = [:]

    var onThumbnailGenerated: (() -> Void)?

    func generateIfNeeded(plant: Plant, completion: @escaping (UIImage?) -> Void) {
        if let cached = PlantThumbnailCache.load(for: plant.id) {
            completion(cached)
            return
        }

        pendingCallbacks[plant.id, default: []].append(completion)

        guard !queuedPlantIDs.contains(plant.id) else { return }
        queuedPlantIDs.insert(plant.id)
        queue.append(plant)
        processNext()
    }

    func enqueue(plants: [Plant]) {
        print("🧩 enqueue called with:", plants.count)
        let newOnes = plants.filter { !PlantThumbnailCache.exists(for: $0.id) }
        print("🧩 new thumbnails to render:", newOnes.count)
        for plant in newOnes where !queuedPlantIDs.contains(plant.id) {
            queuedPlantIDs.insert(plant.id)
            queue.append(plant)
        }
        processNext()
    }

    private func processNext() {
        guard !isRendering else { return }
        guard !queue.isEmpty else {
            // Queue drained — release the singleton ARView's scene so its
            // internal RealityKit mesh/texture caches can shrink. The ARView
            // itself stays alive for the next catalog open.
            ThumbnailRenderHost.shared.releaseScene()
            return
        }

        let plant = queue.removeFirst()
        print("🎬 rendering:", plant.name, "id:", plant.id)
        print("🎬 modelURL:", plant.modelURL ?? "nil")

        isRendering = true

        Task {
            do {
                let url = try await plant.getModelURL()
                renderer.render(usdzURL: url) { image in
                    if let image {
                        PlantThumbnailCache.save(image, plantID: plant.id)
                        self.onThumbnailGenerated?()
                    }
                    self.finishPlant(plantID: plant.id, image: image)
                    self.isRendering = false
                    self.processNext()
                }
            } catch {
                print("⚠️ Failed to get model URL for thumbnail:", plant.name, error)
                self.finishPlant(plantID: plant.id, image: nil)
                self.isRendering = false
                self.processNext()
            }
        }
    }

    private func finishPlant(plantID: String, image: UIImage?) {
        queuedPlantIDs.remove(plantID)
        let callbacks = pendingCallbacks.removeValue(forKey: plantID) ?? []
        for callback in callbacks {
            callback(image)
        }
    }
}
