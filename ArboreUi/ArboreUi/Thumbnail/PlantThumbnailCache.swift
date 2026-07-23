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

    // Bump whenever the studio framing/background changes so old renders do
    // not mask fixes after an app update.
    /// Shared by the disk cache and the public thumbnail URL. Changing this
    /// value invalidates both the on-device files and Cloudflare's cached
    /// response after a new thumbnail design is uploaded under the same plant
    /// identifier.
    static let version = "v22"
    private static let designMarkerColor = UIColor(
        red: 94.0 / 255.0,
        green: 28.0 / 255.0,
        blue: 186.0 / 255.0,
        alpha: 1
    )

    static func url(for plantID: String) -> URL {
        directory.appendingPathComponent("\(plantID)_\(version).png")
    }

    static func remoteURL(for plantID: String, baseURL: String) -> URL? {
        guard var components = URLComponents(
            string: "\(baseURL)/models/thumbnails/\(plantID).png"
        ) else {
            return nil
        }

        components.queryItems = [URLQueryItem(name: "v", value: version)]
        return components.url
    }

    static func exists(for plantID: String) -> Bool {
        load(for: plantID) != nil
    }

    static func cachedPlantIDs() -> [String] {
        let suffix = "_\(version).png"
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let ids = files.compactMap { url -> String? in
            let filename = url.lastPathComponent
            guard filename.hasSuffix(suffix) else { return nil }
            let id = String(filename.dropLast(suffix.count))
            return id.isEmpty ? nil : id
        }

        return Set(ids).sorted()
    }

    static func load(for plantID: String) -> UIImage? {
        let fileURL = url(for: plantID)
        guard let image = UIImage(contentsOfFile: fileURL.path) else { return nil }

        if isLegacyThumbnail(image) {
            try? FileManager.default.removeItem(at: fileURL)
            print("🧹 Ancien thumbnail supprimé:", fileURL.path)
            return nil
        }

        return image
    }

    @discardableResult
    static func save(_ image: UIImage, plantID: String) -> UIImage {
        let studioImage = needsStudioBackdrop(image)
            ? imageByCompositingStudioBackdrop(under: image)
            : image
        let cachedImage = applyingCurrentDesignMarker(to: studioImage)
        guard let data = cachedImage.pngData() else { return cachedImage }
        let path = url(for: plantID)
        try? data.write(to: path)
        print("✅ PNG écrit:", path.path)
        return cachedImage
    }

    static func isLegacyThumbnail(_ image: UIImage) -> Bool {
        !hasCurrentDesignMarker(image)
            || isLegacyDarkThumbnail(image)
            || hasLegacyWhiteWallDarkFloor(image)
            || hasTopBackdropSeam(image)
    }

    /// Adds an invisible-at-card-size signature inside the four corners of the
    /// PNG. Server thumbnails are stored as their original PNG bytes, so this
    /// lets the app distinguish a newly generated studio render from every
    /// previous design instead of relying only on visual heuristics.
    static func applyingCurrentDesignMarker(to image: UIImage) -> UIImage {
        let size = CGSize(width: max(image.size.width, 1), height: max(image.size.height, 1))
        let markerSide = max(4, min(size.width, size.height) * 0.035)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            image.draw(in: rect)
            designMarkerColor.setFill()
            for markerRect in [
                CGRect(x: 0, y: 0, width: markerSide, height: markerSide),
                CGRect(x: size.width - markerSide, y: 0, width: markerSide, height: markerSide),
                CGRect(x: 0, y: size.height - markerSide, width: markerSide, height: markerSide),
                CGRect(
                    x: size.width - markerSide,
                    y: size.height - markerSide,
                    width: markerSide,
                    height: markerSide
                )
            ] {
                context.fill(markerRect)
            }
        }
    }

    static func hasCurrentDesignMarker(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }

        let width = cgImage.width
        let height = cgImage.height
        let inset = max(1, Int(Double(min(width, height)) * 0.0175))
        let samplePoints = [
            (inset, inset),
            (max(width - inset - 1, 0), inset),
            (inset, max(height - inset - 1, 0)),
            (max(width - inset - 1, 0), max(height - inset - 1, 0))
        ]

        let expected = (red: UInt8(94), green: UInt8(28), blue: UInt8(186))
        let matchingCorners = samplePoints.reduce(into: 0) { count, point in
            guard let color = sampledRGB(cgImage, point: point) else { return }
            let tolerance = 5
            if abs(Int(color.red) - Int(expected.red)) <= tolerance,
               abs(Int(color.green) - Int(expected.green)) <= tolerance,
               abs(Int(color.blue) - Int(expected.blue)) <= tolerance {
                count += 1
            }
        }
        return matchingCorners >= 3
    }

    private static func sampledRGB(
        _ image: CGImage,
        point: (Int, Int)
    ) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        guard let cropped = image.cropping(to: CGRect(
            x: min(max(point.0, 0), image.width - 1),
            y: min(max(point.1, 0), image.height - 1),
            width: 1,
            height: 1
        )) else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        let didDraw = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                    CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }

        guard didDraw else { return nil }
        return (pixel[0], pixel[1], pixel[2])
    }

    private static func isLegacyDarkThumbnail(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }

        let gridSize = 8
        let bytesPerPixel = 4
        let bytesPerRow = gridSize * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: gridSize * gridSize * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
            CGBitmapInfo.byteOrder32Big.rawValue

        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: gridSize,
                height: gridSize,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: gridSize, height: gridSize)
            )
            return true
        }

        guard didDraw else { return false }

        let samplePoints = [
            (0, 0), (3, 0), (7, 0),
            (0, 2), (7, 2),
            (0, 4), (7, 4),
            (0, 7), (3, 7), (7, 7)
        ]

        var opaqueSamples = 0
        var opaqueDarkSamples = 0

        for (x, y) in samplePoints {
            let index = ((y * gridSize) + x) * bytesPerPixel
            let red = Float(pixels[index])
            let green = Float(pixels[index + 1])
            let blue = Float(pixels[index + 2])
            let alpha = pixels[index + 3]

            guard alpha > 230 else { continue }

            opaqueSamples += 1
            let brightness = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
            if brightness < 55 {
                opaqueDarkSamples += 1
            }
        }

        return opaqueSamples >= 8 && opaqueDarkSamples >= 7
    }

    private static func hasLegacyWhiteWallDarkFloor(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }

        let gridSize = 12
        let bytesPerPixel = 4
        let bytesPerRow = gridSize * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: gridSize * gridSize * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
            CGBitmapInfo.byteOrder32Big.rawValue

        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: gridSize,
                height: gridSize,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: gridSize, height: gridSize)
            )
            return true
        }

        guard didDraw else { return false }

        let wallSamples = [(1, 1), (6, 1), (10, 1), (1, 3), (10, 3)]
        var brightWallSamples = 0

        for point in wallSamples {
            if sampledBrightness(pixels, gridSize: gridSize, point: point) > 225 {
                brightWallSamples += 1
            }
        }

        return brightWallSamples >= 2
    }

    /// Detects the pale horizontal strip produced by the former studio wall.
    /// Edge samples avoid confusing a light-colored plant with the backdrop.
    private static func hasTopBackdropSeam(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }

        let gridSize = 20
        let bytesPerPixel = 4
        let bytesPerRow = gridSize * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: gridSize * gridSize * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
            CGBitmapInfo.byteOrder32Big.rawValue

        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: gridSize,
                height: gridSize,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: gridSize, height: gridSize))
            return true
        }

        guard didDraw else { return false }

        let edgeColumns = [1, 2, gridSize - 3, gridSize - 2]
        func hasBrightSeam(edgeRow: Int, innerRow: Int) -> Bool {
            let edge = edgeColumns.map {
                sampledBrightness(pixels, gridSize: gridSize, point: ($0, edgeRow))
            }
            let inner = edgeColumns.map {
                sampledBrightness(pixels, gridSize: gridSize, point: ($0, innerRow))
            }
            let edgeAverage = edge.reduce(0, +) / Float(edge.count)
            let innerAverage = inner.reduce(0, +) / Float(inner.count)
            return edgeAverage > 185 && edgeAverage - innerAverage > 10
        }

        // Core Graphics bitmap rows may be vertically flipped depending on
        // the source orientation, so inspect both physical edges.
        return hasBrightSeam(edgeRow: 1, innerRow: 4)
            || hasBrightSeam(edgeRow: gridSize - 2, innerRow: gridSize - 5)
    }

    private static func sampledBrightness(
        _ pixels: [UInt8],
        gridSize: Int,
        point: (Int, Int)
    ) -> Float {
        let index = ((point.1 * gridSize) + point.0) * 4
        let red = Float(pixels[index])
        let green = Float(pixels[index + 1])
        let blue = Float(pixels[index + 2])
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    private static func needsStudioBackdrop(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }

        switch cgImage.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return false
        default:
            break
        }

        let gridSize = 6
        let bytesPerPixel = 4
        let bytesPerRow = gridSize * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: gridSize * gridSize * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
            CGBitmapInfo.byteOrder32Big.rawValue

        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: gridSize,
                height: gridSize,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: gridSize, height: gridSize)
            )
            return true
        }

        guard didDraw else { return false }

        for index in stride(from: 3, to: pixels.count, by: bytesPerPixel) {
            if pixels[index] < 245 {
                return true
            }
        }

        return false
    }

    private static func imageByCompositingStudioBackdrop(under image: UIImage) -> UIImage {
        let size = CGSize(
            width: max(image.size.width, 1),
            height: max(image.size.height, 1)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let rect = CGRect(origin: .zero, size: size)
            let floorHeight = size.height * 0.38
            let wallHeight = size.height - floorHeight
            let wallRect = CGRect(x: 0, y: 0, width: size.width, height: wallHeight)
            let floorRect = CGRect(x: 0, y: wallHeight, width: size.width, height: floorHeight)

            let wallColor = UIColor(white: 0.72, alpha: 1.0)
            let floorColor = UIColor(red: 0.58, green: 0.57, blue: 0.52, alpha: 1.0)

            wallColor.setFill()
            rendererContext.fill(rect)

            wallColor.setFill()
            rendererContext.fill(wallRect)
            floorColor.setFill()
            rendererContext.fill(floorRect)
            if let floor = UIImage(named: "studio_floor") {
                drawAspectFill(floor, in: floorRect, alpha: 0.55)
            }

            drawHorizonShade(in: CGRect(
                x: 0,
                y: wallHeight - 6,
                width: size.width,
                height: min(28, size.height * 0.12)
            ))
            drawSoftPlantShadow(size: size, wallHeight: wallHeight, floorHeight: floorHeight)

            image.draw(in: rect)
        }
    }

    private static func drawAspectFill(
        _ image: UIImage,
        in rect: CGRect,
        alpha: CGFloat = 1.0
    ) {
        guard image.size.width > 0, image.size.height > 0 else { return }

        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        image.draw(in: drawRect, blendMode: .normal, alpha: alpha)
    }

    private static func drawHorizonShade(in rect: CGRect) {
        guard rect.width > 0, rect.height > 0,
              let context = UIGraphicsGetCurrentContext(),
              let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.black.withAlphaComponent(0.10).cgColor,
                    UIColor.black.withAlphaComponent(0.03).cgColor,
                    UIColor.clear.cgColor
                ] as CFArray,
                locations: [0, 0.55, 1]
              ) else {
            return
        }

        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
        context.restoreGState()
    }

    private static func drawSoftPlantShadow(
        size: CGSize,
        wallHeight: CGFloat,
        floorHeight: CGFloat
    ) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let shadowRect = CGRect(
            x: size.width * 0.20,
            y: wallHeight + floorHeight * 0.24,
            width: size.width * 0.60,
            height: size.height * 0.075
        )

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: size.height * 0.006),
            blur: min(size.width, size.height) * 0.045,
            color: UIColor.black.withAlphaComponent(0.09).cgColor
        )
        context.setFillColor(UIColor.black.withAlphaComponent(0.045).cgColor)
        context.fillEllipse(in: shadowRect)
        context.restoreGState()
    }
}
