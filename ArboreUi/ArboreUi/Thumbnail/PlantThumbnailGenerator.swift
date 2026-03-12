import Foundation

@MainActor
final class PlantThumbnailGenerator: ObservableObject {

    private let renderer = PlantThumbnailRenderer()
    private var queue: [Plant] = []
    private var isRendering = false

    var onThumbnailGenerated: (() -> Void)?

    func enqueue(plants: [Plant]) {
        print("🧩 enqueue called with:", plants.count)
        let newOnes = plants.filter { !PlantThumbnailCache.exists(for: $0.id) }
        print("🧩 new thumbnails to render:", newOnes.count)
        queue.append(contentsOf: newOnes)
        processNext()
    }

    private func processNext() {
        guard !isRendering, !queue.isEmpty else { return }

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
                    self.isRendering = false
                    self.processNext()
                }
            } catch {
                print("⚠️ Failed to get model URL for thumbnail:", plant.name, error)
                self.isRendering = false
                self.processNext()
            }
        }
    }
}
