import Foundation
import ImageIO
import UniformTypeIdentifiers

// ReductionVignette — ramener un rendu de vignette à la taille servie. (#524)
//
// Le renderer rend GRAND : la cible fait 1024×1280 points, et sur un appareil
// @3x ça donne 3072×3840 pixels pour une dizaine de mégaoctets. Les vignettes
// réellement servies font 720×900 pour un demi-mégaoctet. La réduction n'est
// donc pas une optimisation accessoire : sans elle, le fichier dépasse les 8 Mo
// que le backend accepte (`maxThumbnailBytes`) et l'envoi prend un 413.
//
// Elle vivait en `private static` dans `DebugThumbnailGeneratorView`, derrière
// `#if DEBUG`, donc inatteignable depuis ailleurs. La génération hors app
// (`GenerationVignettesTests`) a écrit 123 PNG de 3072×3840 et 1,3 Go au total
// avant que la comparaison avec le volume servi ne le montre. Deux chemins qui
// produisent la même chose doivent partager l'étape qui la met en forme, sinon
// le second réapprend l'invariant à ses frais.

enum ReductionVignette {

    /// Côté le plus long, en pixels, des vignettes servies.
    ///
    /// Mesuré sur les 123 fichiers en service : toutes font 720×900, soit 900
    /// sur le grand côté. La valeur n'est donc pas un réglage à ajuster au
    /// goût — elle décrit ce que le parc reçoit déjà.
    static let cotePixelsMax = 900

    /// Réduit un PNG au gabarit servi.
    ///
    /// Rend les octets d'origine quand la réduction échoue, plutôt que rien :
    /// une vignette trop lourde reste rattrapable à l'envoi, une vignette
    /// absente est une plante sans image.
    static func reduire(fichier: URL, cotePixelsMax: Int = cotePixelsMax) throws -> Data {
        try autoreleasepool {
            let brut = { try Data(contentsOf: fichier) }

            let optionsSource: [CFString: Any] = [kCGImageSourceShouldCache: false]
            guard let source = CGImageSourceCreateWithURL(
                fichier as CFURL, optionsSource as CFDictionary) else {
                return try brut()
            }

            let optionsVignette: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: cotePixelsMax,
            ]
            guard let reduite = CGImageSourceCreateThumbnailAtIndex(
                source, 0, optionsVignette as CFDictionary) else {
                return try brut()
            }

            let donnees = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                donnees, UTType.png.identifier as CFString, 1, nil) else {
                return try brut()
            }
            CGImageDestinationAddImage(destination, reduite, nil)
            guard CGImageDestinationFinalize(destination) else {
                return try brut()
            }
            return donnees as Data
        }
    }

    /// Même réduction, depuis des octets déjà en mémoire.
    ///
    /// Passe par un fichier temporaire parce qu'ImageIO lit une URL sans
    /// charger l'image entière, ce qui compte à 3072×3840 : la version en
    /// mémoire tiendrait les deux représentations à la fois.
    static func reduire(png: Data, cotePixelsMax: Int = cotePixelsMax) throws -> Data {
        let temporaire = FileManager.default.temporaryDirectory
            .appendingPathComponent("reduction-\(UUID().uuidString).png")
        try png.write(to: temporaire)
        defer { try? FileManager.default.removeItem(at: temporaire) }
        return try reduire(fichier: temporaire, cotePixelsMax: cotePixelsMax)
    }
}
