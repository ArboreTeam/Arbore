import UIKit
import CoreImage

/// Gestionnaire global des filtres daltoniens appliqués à toute l'application
class ColorBlindnessFilterManager {
    static let shared = ColorBlindnessFilterManager()
    
    private var currentFilter: String = "Default"
    private var overlayWindow: UIWindow?
    private var windowObserver: NSObjectProtocol?
    
    private init() {
        setupWindowObserver()
    }
    
    private func setupWindowObserver() {
        // Observer pour détecter les nouvelles fenêtres
        windowObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Réappliquer le filtre à toutes les fenêtres quand une nouvelle devient active
            if let currentFilter = self?.currentFilter, currentFilter != "Default" {
                self?.applyFilterToAllWindows(filterType: currentFilter)
            }
        }
    }
    
    deinit {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func applyFilter(_ filterType: String, to window: UIWindow? = nil) {
        currentFilter = filterType
        
        // Retirer l'ancien filtre
        removeFilter()
        
        guard filterType != "Default" else { return }
        
        // Appliquer le filtre à toutes les fenêtres de l'application
        applyFilterToAllWindows(filterType: filterType)
    }
    
    private func applyFilterToAllWindows(filterType: String) {
        // Obtenir toutes les fenêtres de toutes les scènes connectées
        let allWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        
        for window in allWindows {
            applyColorMatrixToLayer(window.layer, filterType: filterType)
        }
    }
    
    private func applyColorMatrixToLayer(_ layer: CALayer, filterType: String) {
        let filter = CIFilter(name: "CIColorMatrix")
        
        switch filterType {
        case "Protanopia":
            // Matrice pour protanopie (déficit rouge)
            filter?.setValue(CIVector(x: 0.567, y: 0.433, z: 0, w: 0), forKey: "inputRVector")
            filter?.setValue(CIVector(x: 0.558, y: 0.442, z: 0, w: 0), forKey: "inputGVector")
            filter?.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
            filter?.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            
        case "Deuteranopia":
            // Matrice pour deutéranopie (déficit vert)
            filter?.setValue(CIVector(x: 0.625, y: 0.375, z: 0, w: 0), forKey: "inputRVector")
            filter?.setValue(CIVector(x: 0.7, y: 0.3, z: 0, w: 0), forKey: "inputGVector")
            filter?.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
            filter?.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            
        case "Tritanopia":
            // Matrice pour tritanopie (déficit bleu)
            filter?.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
            filter?.setValue(CIVector(x: 0, y: 0.95, z: 0.05, w: 0), forKey: "inputGVector")
            filter?.setValue(CIVector(x: 0, y: 0.43, z: 0.57, w: 0), forKey: "inputBVector")
            filter?.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            
        default:
            return
        }
        
        if let filter = filter {
            layer.filters = [filter]
        }
    }
    
    func removeFilter() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
        
        // Retirer les filtres de toutes les fenêtres
        let allWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        
        for window in allWindows {
            window.layer.filters = nil
        }
    }
    
    func getCurrentFilter() -> String {
        return currentFilter
    }
}
