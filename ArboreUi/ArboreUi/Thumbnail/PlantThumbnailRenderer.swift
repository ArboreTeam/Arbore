import UIKit
import RealityKit
import simd

@MainActor
final class PlantThumbnailRenderer {

    private let arView: ARView
    private let wallColor = UIColor(white: 0.78, alpha: 1.0)
    private let floorFallbackColor = UIColor(red: 0.58, green: 0.57, blue: 0.52, alpha: 1.0)
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

        self.arView.environment.background = .color(wallColor)
        self.arView.renderOptions.insert(.disableHDR)
        self.arView.environment.lighting.intensityExponent = 0.85

        self.floorTexture = try? TextureResource.load(named: "studio_floor")
        self.wallTexture = try? TextureResource.load(named: "studio_wall")
    }

    func render(usdzURL: URL, upAxis: String?, completion: @escaping (UIImage?) -> Void) {
        Task { @MainActor in
            do {
                arView.scene.anchors.removeAll()
                let anchor = AnchorEntity(world: .zero)

                let model = try await ModelEntity(contentsOf: usdzURL)
                let modelKey = usdzURL.deletingPathExtension().lastPathComponent

                // Plant at native scale, matching AR placement.
                let isZUp = (upAxis?.uppercased() == "Z")
                if isZUp {
                    model.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
                } else {
                    model.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
                }

                var b = model.visualBounds(relativeTo: nil)
                model.position.y = -b.min.y

                b = model.visualBounds(relativeTo: nil)
                let center = b.center
                model.position.x -= center.x
                model.position.z -= center.z

                b = model.visualBounds(relativeTo: nil)
                let plantH = max(b.extents.y, 0.001)
                let plantW = max(b.extents.x, 0.001)
                let plantD = max(b.extents.z, 0.001)
                let plantMaxHoriz = max(plantW, plantD)

                print("Thumbnail", modelKey, "H=", plantH, "W=", plantW, "D=", plantD)

                let halfVFov = (cameraFOVDegrees / 2) * .pi / 180
                let halfVTan = tan(halfVFov)
                let aspectRatio: Float = 1024.0 / 1280.0
                let halfHTan = halfVTan * aspectRatio

                let distForH = (plantH / 2) / (halfVTan * fillFactor)
                let distForW = (plantMaxHoriz / 2) / (halfHTan * fillFactor)
                let distance = max(distForH, distForW)

                let pitchRad = cameraPitchDegrees * .pi / 180
                let lookAtY = plantH * 0.45
                let cameraY = lookAtY + distance * sin(pitchRad)
                let cameraZ = plantD / 2 + distance * cos(pitchRad)

                let sceneScale = max(plantH, plantMaxHoriz, distance)
                let studioSize = sceneScale * 10

                let floorMesh = Self.makeTiledPlane(
                    width: studioSize,
                    depth: studioSize,
                    uScale: studioSize * 0.8,
                    vScale: studioSize * 0.8
                )
                let floor = ModelEntity(mesh: floorMesh)
                var floorMat = PhysicallyBasedMaterial()
                if let floorTexture {
                    floorMat.baseColor = .init(
                        tint: UIColor(white: 0.98, alpha: 1.0),
                        texture: .init(floorTexture)
                    )
                } else {
                    floorMat.baseColor = .init(tint: floorFallbackColor)
                }
                floorMat.roughness = .init(floatLiteral: 0.95)
                floorMat.metallic = .init(floatLiteral: 0.0)
                floor.model?.materials = [floorMat]
                floor.position = [0, -0.001, 0]

                let wallZ: Float = -(plantD + distance * 0.3)
                let wallMesh = Self.makeTiledPlane(
                    width: studioSize,
                    depth: studioSize,
                    uScale: studioSize * 0.5,
                    vScale: studioSize * 0.5
                )
                let backdrop = ModelEntity(mesh: wallMesh)
                var wallMat = UnlitMaterial(color: wallColor)
                if let wallTexture {
                    wallMat.color = .init(
                        tint: wallColor,
                        texture: .init(wallTexture)
                    )
                }
                backdrop.model?.materials = [wallMat]
                backdrop.position = [0, studioSize / 2, wallZ]
                backdrop.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])

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
                print("Render error:", error.localizedDescription)
                completion(nil)
            }
        }
    }

    // MARK: - Tiled Plane

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

    private func dumpEntity(_ entity: Entity, level: Int = 0) {
        let indent = String(repeating: "  ", count: level)
        print("\(indent)- \(entity.name) [\(type(of: entity))]")
        print("\(indent)  children: \(entity.children.count)")
        print("\(indent)  position: \(entity.position)")
        print("\(indent)  scale: \(entity.scale)")

        if let modelEntity = entity as? ModelEntity,
           let comp = modelEntity.model {
            print("\(indent)  ModelComponent materials: \(comp.materials.count)")
        }

        for child in entity.children {
            dumpEntity(child, level: level + 1)
        }
    }
}
