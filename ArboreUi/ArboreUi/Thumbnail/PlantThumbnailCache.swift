import UIKit

struct PlantThumbnailCache {

    private static var directory: URL {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlantThumbs", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    private static let version = "v15"

    static func url(for plantID: String) -> URL {
        directory.appendingPathComponent("\(plantID)_\(version).png")
    }

    static func exists(for plantID: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: plantID).path)
    }

    static func load(for plantID: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: plantID).path)
    }

    static func save(_ image: UIImage, plantID: String) {
        guard let data = image.pngData() else { return }
        let path = url(for: plantID)
        try? data.write(to: path)
        print("✅ PNG écrit:", path.path)
    }
}
