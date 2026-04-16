import UIKit
import RealityKit
import simd

@MainActor
final class PlantThumbnailRenderer {

    private let arView: ARView

    private var floorTexture: TextureResource?
    private var wallTexture: TextureResource?

    // Auto-frame camera parameters. The plant is kept at its native USDZ
    // scale (real-world meters, just like AR placement) and the camera
    // moves per-plant to frame it. This makes thumbnails proportional to
    // the plant's actual size without per-plant hand-tuning.
    private let cameraFOVDegrees: Float = 60
    private let fillFactor: Float = 0.65

    init() {
        self.arView = ThumbnailRenderHost.shared.arView
        self.arView.frame = CGRect(x: 0, y: 0, width: 1024, height: 1280)

        // ✅ Fond légèrement gris (au lieu de blanc pur)
        self.arView.environment.background = .color(UIColor(white: 0.95, alpha: 1.0))

        // ✅ Désactive le HDR pour calmer les highlights
        self.arView.renderOptions.insert(.disableHDR)

        // ✅ Calme un peu le rendu global (optionnel mais efficace)
        self.arView.environment.lighting.intensityExponent = 0.85

        // Assets.xcassets
        self.floorTexture = try? TextureResource.load(named: "studio_floor")
        self.wallTexture  = try? TextureResource.load(named: "studio_wall")

        // Debug (à laisser 2 runs)
        print("🧱 floorTexture:", floorTexture == nil ? "nil" : "ok")
        print("🧱 wallTexture :", wallTexture  == nil ? "nil" : "ok")
    }

    func render(usdzURL: URL, completion: @escaping (UIImage?) -> Void) {
        Task { @MainActor in
            do {
                arView.scene.anchors.removeAll()
                let anchor = AnchorEntity(world: .zero)

                let model = try await ModelEntity(contentsOf: usdzURL)

                let modelKey = usdzURL.deletingPathExtension().lastPathComponent

                // --- 1) Plant at NATIVE scale (same as AR placement).
                // No manual scaling — USDZ meters are real meters, and the
                // camera auto-frames the plant below.
                model.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])

                // Bottom-align: plant sits on the floor at y=0, centered x/z.
                var b = model.visualBounds(relativeTo: nil)
                model.position.y = -b.min.y
                b = model.visualBounds(relativeTo: nil)
                let center = b.center
                model.position.x -= center.x
                model.position.z -= center.z

                // Final bounds after positioning.
                b = model.visualBounds(relativeTo: nil)
                let plantH = max(b.extents.y, 0.001)
                let plantW = max(b.extents.x, 0.001)
                let plantD = max(b.extents.z, 0.001)
                let plantMaxHoriz = max(plantW, plantD)

                print("🌿 Thumbnail", modelKey, "native H=", plantH, "W=", plantW, "D=", plantD)

                // --- 2) Camera distance & framing (computed first so the
                // backdrop can be sized to cover the visible frustum)
                let halfFovTan = tan((cameraFOVDegrees / 2) * .pi / 180)
                let aspectRatio: Float = 1024.0 / 1280.0  // arView W/H
                let verticalNeed = plantH
                let horizontalNeed = (plantMaxHoriz * 2) / aspectRatio
                let neededExtent = max(verticalNeed, horizontalNeed)
                let distance = (neededExtent / 2) / (halfFovTan * fillFactor)

                let lookAtY = plantH / 2
                let cameraZ = plantD / 2 + distance
                let wallZ = -plantD * 1.5 - 0.1

                // --- 3) Studio backdrop sized from camera frustum.
                // At the wall's Z position, compute the visible rect and
                // make the wall 50% bigger to guarantee full coverage.
                let camToWallDist = cameraZ - wallZ
                let visibleHAtWall = 2 * camToWallDist * halfFovTan
                let visibleWAtWall = visibleHAtWall * aspectRatio
                let wallWidth = visibleWAtWall * 1.5
                let wallHeight = visibleHAtWall * 1.5

                // Floor needs to cover from the plant outward toward the
                // camera and behind the plant toward the wall. Using the
                // camera distance as the base gives plenty of margin.
                let floorExtent = max(cameraZ * 3, plantMaxHoriz * 6, 3.0)

                let floorMesh = Self.makeTiledPlane(
                    width: floorExtent,
                    depth: floorExtent,
                    uScale: floorExtent,
                    vScale: floorExtent
                )
                let floor = ModelEntity(mesh: floorMesh)

                var floorMat = PhysicallyBasedMaterial()
                if let floorTexture {
                    floorMat.baseColor = .init(tint: .white, texture: .init(floorTexture))
                } else {
                    floorMat.baseColor = .init(tint: UIColor(white: 0.78, alpha: 1.0))
                }
                floorMat.roughness = .init(floatLiteral: 0.95)
                floorMat.metallic  = .init(floatLiteral: 0.0)
                floor.model?.materials = [floorMat]
                floor.position = [0, -0.001, 0]

                let wallMesh = Self.makeTiledPlane(
                    width: wallWidth,
                    depth: wallHeight,
                    uScale: wallWidth / 1.8,
                    vScale: wallHeight / 1.8
                )
                let backdrop = ModelEntity(mesh: wallMesh)

                var wallMat = UnlitMaterial(color: .white)
                if let wallTexture {
                    wallMat.color = .init(
                        tint: UIColor(white: 0.92, alpha: 1.0),
                        texture: .init(wallTexture)
                    )
                } else {
                    wallMat.color = .init(tint: UIColor(white: 0.92, alpha: 1.0))
                }
                backdrop.model?.materials = [wallMat]
                backdrop.position = [0, lookAtY, wallZ]
                backdrop.orientation = simd_quatf(angle: .pi/2, axis: [1, 0, 0])

                // --- 3) Lumières (✅ clés baissées)
                let light = DirectionalLight()
                light.light.intensity = 25000
                light.light.color = UIColor(white: 0.98, alpha: 1.0)
                light.shadow = DirectionalLightComponent.Shadow(
                    maximumDistance: 3,
                    depthBias: 3e-4
                )
                light.orientation =
                    simd_quatf(angle: -.pi/3, axis: [1, 0, 0]) *
                    simd_quatf(angle: .pi/6, axis: [0, 1, 0])

                // ✅ Fill/Rim positionnés relativement à la taille de la plante
                // (inverse-square: intensity scales with distance²)
                let lightOffset = max(plantMaxHoriz, plantH) * 1.2
                let lightIntensity: Float = 200 * (lightOffset * lightOffset) / (1.0 * 1.0)

                let fill = PointLight()
                fill.light.intensity = lightIntensity
                fill.light.color = UIColor(white: 0.92, alpha: 1.0)
                fill.position = [lightOffset, plantH * 0.9, lightOffset]

                let rim = PointLight()
                rim.light.intensity = lightIntensity
                rim.light.color = UIColor(white: 0.92, alpha: 1.0)
                rim.position = [-lightOffset, plantH * 0.8, -lightOffset]

                // --- 5) Caméra auto-framing (distance/lookAtY calculés plus haut)
                let camera = PerspectiveCamera()
                camera.camera.fieldOfViewInDegrees = cameraFOVDegrees
                camera.position = [0, lookAtY, cameraZ]
                camera.look(
                    at: [0, lookAtY, 0],
                    from: camera.position,
                    relativeTo: nil
                )

                anchor.addChild(floor)
                anchor.addChild(backdrop)
                anchor.addChild(model)
                anchor.addChild(light)
                anchor.addChild(fill)
                anchor.addChild(rim)
                anchor.addChild(camera)

                arView.scene.addAnchor(anchor)

                arView.setNeedsLayout()
                arView.layoutIfNeeded()

                let view = self.arView
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    view.snapshot(saveToHDR: false) { image in
                        completion(image)
                    }
                }
            } catch {
                print("❌ Render error:", error.localizedDescription)
                completion(nil)
            }
        }
    }

    private func normalizeModelKey(_ key: String) -> String {
        key
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    // MARK: - Tiled Plane (UVs qui se répètent)

    private static func makeTiledPlane(
        width: Float,
        depth: Float,
        uScale: Float,
        vScale: Float
    ) -> MeshResource {

        let hw = width / 2
        let hd = depth / 2

        var desc = MeshDescriptor()
        desc.positions = .init([
            SIMD3(-hw, 0, -hd),
            SIMD3( hw, 0, -hd),
            SIMD3(-hw, 0,  hd),
            SIMD3( hw, 0,  hd)
        ])

        desc.normals = .init([
            SIMD3(0, 1, 0),
            SIMD3(0, 1, 0),
            SIMD3(0, 1, 0),
            SIMD3(0, 1, 0)
        ])

        desc.textureCoordinates = .init([
            SIMD2(0, 0),
            SIMD2(uScale, 0),
            SIMD2(0, vScale),
            SIMD2(uScale, vScale)
        ])

        desc.primitives = .triangles([
            0, 2, 1,
            1, 2, 3
        ])

        do {
            return try MeshResource.generate(from: [desc])
        } catch {
            return .generatePlane(width: width, depth: depth)
        }
    }
}
