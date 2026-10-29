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
        if let cached = PlantThumbnailCache.load(for: plant.id, empreinte: plant.versions?.thumbnail) {
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
        let newOnes = plants.filter { !PlantThumbnailCache.exists(for: $0.id, empreinte: $0.versions?.thumbnail) }
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

                // Une plante recoupée se montre AVEC son pot : sans lui, la
                // vignette du catalogue et le rendu AR montreraient deux objets
                // différents. L'échec du pot ne doit pas coûter la vignette —
                // la plante nue se voit et se corrige, une carte vide non.
                var pot: (url: URL, pose: PotPlacement)?
                if let lie = plant.potEtPose() {
                    do {
                        let potURL = try await ModelCacheManager.shared.getModelURL(
                            for: lie.pot.modelURL, version: lie.pot.version)
                        pot = (potURL, lie.pose)
                    } catch {
                        print("🎬 pot indisponible pour", plant.name, error)
                    }
                }

                renderer.render(usdzURL: url, upAxis: plant.upAxis, pot: pot) { image in
                    Task { @MainActor in
                        var cachedImage = image
                        if let image {
                            cachedImage = await Task.detached(priority: .utility) {
                                PlantThumbnailCache.save(image, plantID: plant.id,
                                         empreinte: plant.versions?.thumbnail)
                            }.value
                            self.onThumbnailGenerated?()
                        }
                        self.finishPlant(plantID: plant.id, image: cachedImage)
                        self.isRendering = false
                        self.processNext()
                    }
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
