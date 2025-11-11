import SwiftUI
import UIKit

// Modificateur qui applique un filtre de couleur CoreImage à toute la vue
struct ColorBlindnessFilterModifier: ViewModifier {
    let filterType: String
    
    func body(content: Content) -> some View {
        if filterType == "Default" {
            content
        } else {
            content
                .overlay(
                    ColorBlindnessFilterView(filterType: filterType)
                        .allowsHitTesting(false)
                        .blendMode(.normal)
                )
        }
    }
}

struct ColorBlindnessFilterView: UIViewRepresentable {
    let filterType: String
    
    func makeUIView(context: Context) -> UIView {
        let view = ColorFilterUIView()
        view.filterType = filterType
        view.backgroundColor = .clear
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let filterView = uiView as? ColorFilterUIView {
            filterView.filterType = filterType
            filterView.setNeedsDisplay()
        }
    }
}

class ColorFilterUIView: UIView {
    var filterType: String = "Default"
    
    override func draw(_ rect: CGRect) {
        // Eviter l'avertissement "context defined but never used"
        // On ne fait rien pour l'instant si pas de filtre.
        guard filterType != "Default" else { return }
        // Placeholder pour future implémentation CoreImage / CALayer
    }
}

extension View {
    func applyColorBlindnessFilter(_ scheme: String) -> some View {
        self.modifier(ColorBlindnessFilterModifier(filterType: scheme))
    }
}
