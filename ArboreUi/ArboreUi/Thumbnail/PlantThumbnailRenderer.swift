import UIKit
import RealityKit
import simd

@MainActor
final class PlantThumbnailRenderer {

    private let arView: ARView
    private var shadowTexture: TextureResource?

    init() {
        self.arView = ThumbnailRenderHost.shared.arView
        self.arView.frame = CGRect(x: 0, y: 0, width: 1024, height: 1280)
        self.arView.environment.background = .color(.white)

        // Neutralise le "boost" qui peut cramer les verts
        self.arView.environment.lighting.intensityExponent = 1.0

        // Précharge la texture d'ombre (Assets.xcassets: "soft_shadow")
        self.shadowTexture = try? TextureResource.load(named: "soft_shadow")
    }

    func render(usdzURL: URL, completion: @escaping (UIImage?) -> Void) {
        Task { @MainActor in
            do {
                arView.scene.anchors.removeAll()
                let anchor = AnchorEntity(world: .zero)

                let model = try await ModelEntity.loadModel(contentsOf: usdzURL)

                // --- 1) NORMALISATION (tes valeurs inchangées)
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

                // --- 2) Studio: sol + backdrop (inchangé)
                let floor = ModelEntity(mesh: .generatePlane(width: 3.0, depth: 3.0))
                var floorMat = PhysicallyBasedMaterial()
                floorMat.baseColor = .init(tint: UIColor(white: 0.92, alpha: 1.0))
                floorMat.roughness = .init(floatLiteral: 0.95)
                floorMat.metallic  = .init(floatLiteral: 0.0)
                floor.model?.materials = [floorMat]
                floor.position = [0, -0.001, 0]

                let backdrop = ModelEntity(mesh: .generatePlane(width: 3.6, depth: 3.6))
                backdrop.model?.materials = [UnlitMaterial(color: UIColor(white: 0.96, alpha: 1.0))]
                backdrop.position = [0, 1.1, -1.3]
                backdrop.orientation = simd_quatf(angle: .pi/2, axis: [1, 0, 0])

                // ✅ Ombre ronde via texture (compatible toutes versions)
                // plane horizontal avec texture alpha
                let contactShadow = ModelEntity(mesh: .generatePlane(width: 0.75, depth: 0.75))
                var shadowMat = UnlitMaterial()

                if let shadowTexture {
                    shadowMat.color = .init(tint: .white, texture: .init(shadowTexture))
                } else {
                    // Fallback si l'asset n'est pas trouvé
                    shadowMat.color = .init(tint: UIColor.black.withAlphaComponent(0.12))
                }

                contactShadow.model?.materials = [shadowMat]
                contactShadow.position = [0, 0.0005, 0]

                // --- 3) Lumière (tes valeurs inchangées) + fill douce
                let light = DirectionalLight()
                light.light.intensity = 70000
                light.shadow = DirectionalLightComponent.Shadow(maximumDistance: 6, depthBias: 1e-4)
                light.orientation =
                    simd_quatf(angle: -.pi/3, axis: [1, 0, 0]) *
                    simd_quatf(angle: .pi/6, axis: [0, 1, 0])

                let fill = PointLight()
                fill.light.intensity = 1200
                fill.light.color = .white
                fill.position = [0.6, 1.2, 1.0]

                // --- 4) Caméra FIXE (tes valeurs inchangées)
                let camera = PerspectiveCamera()
                camera.position = [0, 0.75, 2.0]
                camera.look(at: [0, 0.75, 0], from: camera.position, relativeTo: nil)

                anchor.addChild(floor)
                anchor.addChild(backdrop)
                anchor.addChild(contactShadow)
                anchor.addChild(model)
                anchor.addChild(light)
                anchor.addChild(fill)
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
}
