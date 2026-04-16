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
    private let cameraFOVDegrees: Float = 35
    private let fillFactor: Float = 0.78
    // Slight downward pitch so the viewer sees the top of the plant and
    // a bit of floor in front, giving a more natural catalog look.
    private let cameraPitchDegrees: Float = 8

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

    func render(usdzURL: URL, upAxis: String?, completion: @escaping (UIImage?) -> Void) {
        Task { @MainActor in
            do {
                arView.scene.anchors.removeAll()
                let anchor = AnchorEntity(world: .zero)

                let model = try await ModelEntity(contentsOf: usdzURL)

                let modelKey = usdzURL.deletingPathExtension().lastPathComponent

                // --- 1) Plant at NATIVE scale (same as AR placement).
                // No manual scaling — USDZ meters are real meters, and the
                // camera auto-frames the plant below.
                //
                // Axis handling driven by the `upAxis` field from the DB:
                // "Z" = Blender-style Z-up USDZ that RealityKit doesn't fully
                // auto-convert; we apply a -π/2 X rotation to stand it up.
                // Anything else (nil, "Y") = standard Y-up, just flip 180°
                // around Y so the plant faces the camera.
                let isZUp = (upAxis?.uppercased() == "Z")
                if isZUp {
                    model.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
                } else {
                    model.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
                }

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

                print("🌿 Thumbnail", modelKey, "H=", plantH, "W=", plantW, "D=", plantD)

                // =====================================================
                // 2) CAMERA — correct frustum math
                // =====================================================
                let halfVFov = (cameraFOVDegrees / 2) * .pi / 180
                let halfVTan = tan(halfVFov)
                let aspectRatio: Float = 1024.0 / 1280.0
                let halfHTan = halfVTan * aspectRatio

                // Distance so the plant fills `fillFactor` of the viewport
                // on whichever axis is the bottleneck.
                let distForH = (plantH / 2) / (halfVTan * fillFactor)
                let distForW = (plantMaxHoriz / 2) / (halfHTan * fillFactor)
                let distance = max(distForH, distForW)

                // Pitch: camera slightly above, looking at plant center.
                // lookAt shifted down a bit (0.45 × plantH) so the pitch
                // doesn't push the plant to the bottom of the frame.
                let pitchRad = cameraPitchDegrees * .pi / 180
                let lookAtY = plantH * 0.45
                let cameraY = lookAtY + distance * sin(pitchRad)
                let cameraZ = plantD / 2 + distance * cos(pitchRad)

                // =====================================================
                // 3) BACKDROP — massively oversized quads (4 vertices
                //    each, zero perf cost) so no edge is EVER visible
                //    regardless of FOV, pitch, or plant proportions.
                // =====================================================
                let sceneScale = max(plantH, plantMaxHoriz, distance)
                let studioSize = sceneScale * 10

                // Floor: horizontal quad at y=0, centred under plant
                let floorMesh = Self.makeTiledPlane(
                    width: studioSize, depth: studioSize,
                    uScale: studioSize * 0.8, vScale: studioSize * 0.8
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

                // Wall: vertical quad, bottom at y=0, behind the plant
                let wallZ: Float = -studioSize / 2
                let wallMesh = Self.makeTiledPlane(
                    width: studioSize, depth: studioSize,
                    uScale: studioSize * 0.5, vScale: studioSize * 0.5
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
                backdrop.position = [0, studioSize / 2, wallZ]
                backdrop.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])

                // =====================================================
                // 4) LIGHTS — scaled to plant dimensions
                // =====================================================
                let light = DirectionalLight()
                light.light.intensity = 25000
                light.light.color = UIColor(white: 0.98, alpha: 1.0)
                light.shadow = DirectionalLightComponent.Shadow(
                    maximumDistance: sceneScale * 3,
                    depthBias: 3e-4
                )
                light.orientation =
                    simd_quatf(angle: -.pi / 3, axis: [1, 0, 0]) *
                    simd_quatf(angle: .pi / 6, axis: [0, 1, 0])

                let lightDist = sceneScale * 1.2
                let lightPower: Float = 200 * (lightDist * lightDist)

                let fill = PointLight()
                fill.light.intensity = lightPower
                fill.light.color = UIColor(white: 0.92, alpha: 1.0)
                fill.position = [lightDist, plantH * 0.9, lightDist]

                let rim = PointLight()
                rim.light.intensity = lightPower
                rim.light.color = UIColor(white: 0.92, alpha: 1.0)
                rim.position = [-lightDist, plantH * 0.8, -lightDist]

                // =====================================================
                // 5) CAMERA placement
                // =====================================================
                let camera = PerspectiveCamera()
                camera.camera.fieldOfViewInDegrees = cameraFOVDegrees
                camera.position = [0, cameraY, cameraZ]
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
