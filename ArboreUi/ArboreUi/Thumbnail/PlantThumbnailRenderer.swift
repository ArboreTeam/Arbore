import UIKit
import RealityKit
import simd

@MainActor
final class PlantThumbnailRenderer {

    private let arView: ARView

    private var floorTexture: TextureResource?
    private var wallTexture: TextureResource?

    private let defaultTargetHeight: Float = 0.02

    // Height in scene units per plant. Tune these values plant-by-plant.
    private let perModelTargetHeight: [String: Float] = [
        "pothos": 0.01,
        "monstera_deliciosa": 0.016,
        "cactus": 0.016,
        "dyspis_lutescens": 0.016,
        "livistona_chinensis": 0.016,
        "pilea": 0.01,
        "chamaedorea_elegans": 1.6,
        "philodendron_birkin_variegata": 1,
        "alocasia_polly": 1,
    ]

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

                // 🔍 DEBUG TREE
                print("=== ENTITY TREE BEFORE TRANSFORMS ===")
                dumpEntity(model)

                // 🔍 DEBUG BOUNDS
                var b = model.visualBounds(relativeTo: nil)
                print("📦 Before any transform")
                print("   min    :", b.min)
                print("   max    :", b.max)
                print("   center :", b.center)
                print("   extents:", b.extents)

                // ✅ Nom du modèle basé sur le nom de fichier (sans extension)
                let modelKey = usdzURL.deletingPathExtension().lastPathComponent

                // --- 1) NORMALISATION + CALIBRATION PAR MODELE
                let normalizedModelKey = normalizeModelKey(modelKey)
                let targetHeight = perModelTargetHeight[normalizedModelKey] ?? defaultTargetHeight

                let currentHeight = max(b.extents.y, 0.0001)
                let s = targetHeight / currentHeight
                model.scale = SIMD3(repeating: s)

                b = model.visualBounds(relativeTo: nil)
                print("📦 After scale")
                print("   min    :", b.min)
                print("   max    :", b.max)
                print("   center :", b.center)
                print("   extents:", b.extents)

                model.position.y = -b.min.y

                b = model.visualBounds(relativeTo: nil)
                print("📦 After ground alignment")
                print("   min    :", b.min)
                print("   max    :", b.max)
                print("   center :", b.center)
                print("   extents:", b.extents)

                let center = b.center
                model.position.x -= center.x
                model.position.z -= center.z

                b = model.visualBounds(relativeTo: nil)
                print("📦 After centering")
                print("   min    :", b.min)
                print("   max    :", b.max)
                print("   center :", b.center)
                print("   extents:", b.extents)

                //model.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])

                // Debug calibration key/size
                print("🌿 Thumbnail modelKey:", modelKey, "| normalized:", normalizedModelKey, "| targetHeight:", targetHeight)

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

                // ✅ Mur unlit un peu moins blanc + texture si dispo
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
                backdrop.position = [0, 1.1, -1.3]
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

                // ✅ Fill/Rim plus faibles pour éviter le “flashy”
                let fill = PointLight()
                fill.light.intensity = 200
                fill.light.color = UIColor(white: 0.92, alpha: 1.0)
                fill.position = [0.6, 1.2, 1.0]

                let rim = PointLight()
                rim.light.intensity = 200
                rim.light.color = UIColor(white: 0.92, alpha: 1.0)
                rim.position = [-0.7, 1.1, -1.0]

                // --- 4) Caméra (inchangée)
                let camera = PerspectiveCamera()
                camera.position = [0, 0.8, 2.05]
                camera.look(
                    at: [0, 0.7, 0],
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

    func dumpEntity(_ entity: Entity, level: Int = 0) {
        let indent = String(repeating: "  ", count: level)
        print("\(indent)• \(entity.name) [\(type(of: entity))]")
        print("\(indent)  children: \(entity.children.count)")
        print("\(indent)  position: \(entity.position)")
        print("\(indent)  scale   : \(entity.scale)")
        
        if let modelEntity = entity as? ModelEntity,
        let comp = modelEntity.model {
            print("\(indent)  ✅ ModelComponent materials: \(comp.materials.count)")
        }
        
        for child in entity.children {
            dumpEntity(child, level: level + 1)
        }
    }
}
