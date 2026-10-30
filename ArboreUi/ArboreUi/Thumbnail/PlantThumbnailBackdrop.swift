import UIKit

/// Décor des vignettes du catalogue : un studio beige chaud et uni, dans la
/// famille du fond de l'app mais plus saturé, pour que la plante ressorte.
///
/// Le fond de page de l'app (#F0EEEA) ne peut pas servir tel quel :
/// `PlantThumbnailCache.isLegacyThumbnail` prend tout mur plus lumineux
/// qu'une luminance de 225 pour l'ancien décor blanc et écarte la vignette.
/// Le mur reste donc sous ce seuil (≈ 212).
enum PlantThumbnailBackdrop {
    /// Mur du studio et fond au-delà du décor.
    static let wall = UIColor(hex: "#E6D2B0")

    /// Albédo du sol, sans texture. L'éclairage du studio, réglé pour la
    /// plante, l'éclaircit et le désature nettement : cette base sombre et
    /// chaude arrive, une fois éclairée, au ton du mur, pour un horizon
    /// presque invisible.
    static let floor = UIColor(hex: "#5A4B33")

    /// Sol tel qu'il apparaît éclairé, pour le rendu de secours en 2D.
    static let litFloor = UIColor(hex: "#E4CFAC")
}
