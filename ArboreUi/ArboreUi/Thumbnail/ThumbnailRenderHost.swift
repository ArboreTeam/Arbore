import UIKit
import RealityKit

@MainActor
final class ThumbnailRenderHost {
    static let shared = ThumbnailRenderHost()

    private var window: UIWindow?
    let arView: ARView

    private init() {
        arView = ARView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        arView.cameraMode = .nonAR
        arView.environment.background = .color(.white)

        // Fenêtre offscreen (mais attachée)
        let win = UIWindow(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.isHidden = true

        vc.view.addSubview(arView)
        arView.isHidden = true // invisible
        win.rootViewController = vc
        win.windowLevel = .alert + 1
        win.isHidden = false

        self.window = win
    }
}
