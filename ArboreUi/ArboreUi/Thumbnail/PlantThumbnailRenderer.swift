import UIKit
import RealityKit
import simd

@MainActor
final class PlantThumbnailRenderer {

    private let arView: ARView

    private var floorTexture: TextureResource?
    private var wallTexture: TextureResource?

    init() {
        self.arView = ThumbnailRenderHost.shared.arView
        self.arView.frame = CGRect(x: 0, y: 0, width: 1024, height: 1280)
        self.arView.environment.background = .color(.white)

        // Neutralise le "boost" qui peut cramer les verts
        self.arView.environment.lighting.intensityExponent = 1.0

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

                let model = try await ModelEntity.loadModel(contentsOf: usdzURL)

                // --- 1) NORMALISATION (inchangée)
                let targetHeight: Float = 0.02

                var b = model.visualBounds(relativeTo: nil)
                let currentHeight = max(b.extents.y, 0.0001)

                let s = targetHeight / currentHeight
                model.scale = SIMD3(repeating: s)

                b = model.visualBounds(relativeTo: nil)
                model.position.y = -b.min.y
                b = model.visualBounds(relativeTo: nil)

                let center = b.center
                model.position.x -= center.x
                model.position.z -= center.z

                model.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])

                // --- 2) Studio: sol + mur (textures + tiling)
                let floorMesh = Self.makeTiledPlane(
                    width: 3.0,
                    depth: 3.0,
                    uScale: 3.0,
                    vScale: 3.0
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
                    width: 3.6,
                    depth: 3.6,
                    uScale: 2.0,
                    vScale: 2.0
                )
                let backdrop = ModelEntity(mesh: wallMesh)

                var wallMat = UnlitMaterial(color: .white)
                if let wallTexture {
                    wallMat.color = .init(tint: .white, texture: .init(wallTexture))
                } else {
                    wallMat.color = .init(tint: UIColor(white: 0.93, alpha: 1.0))
                }
                backdrop.model?.materials = [wallMat]
                backdrop.position = [0, 1.1, -1.3]
                backdrop.orientation = simd_quatf(angle: .pi/2, axis: [1, 0, 0])

                // --- 3) Lumières (POINT 1 APPLIQUÉ ICI)
                let light = DirectionalLight()
                light.light.intensity = 70000
                light.shadow = DirectionalLightComponent.Shadow(
                    maximumDistance: 3,
                    depthBias: 3e-4
                )
                light.orientation =
                    simd_quatf(angle: -.pi/3, axis: [1, 0, 0]) *
                    simd_quatf(angle: .pi/6, axis: [0, 1, 0])

                // 🔽 Fill light volontairement plus faible et plus neutre
                // => verts moins flashy
                let fill = PointLight()
                fill.light.intensity = 350          // ⬅️ AVANT: 500
                fill.light.color = UIColor(white: 0.92, alpha: 1.0)
                fill.position = [0.6, 1.2, 1.0]

                let rim = PointLight()
                rim.light.intensity = 350
                rim.light.color = UIColor(white: 0.92, alpha: 1.0)
                rim.position = [-0.7, 1.1, -1.0]

                // --- 4) Caméra (POINT 3 : micro-ajustement)
                let camera = PerspectiveCamera()
                camera.position = [0, 0.8, 2.05]     // ⬅️ un poil plus haut / plus loin
                camera.look(
                    at: [0, 0.7, 0],                 // ⬅️ regard légèrement abaissé
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
