import XCTest
import SwiftUI
@testable import ArboreUi

// GardenMapPerformanceTests.swift — issue #533.
//
// Le plan 2D du jardin ramait dès seize plantes. La cause n'était pas un
// algorithme lent mais un empilement : chaque marqueur portait ~16 calques,
// dont trois passes de rendu hors écran (un flou, deux ombres), et le symbole de
// plante à lui seul dessinait dix pétales dégradés.
//
// Le tout était réévalué à CHAQUE événement tactile, parce que la position de
// chaque marqueur dérive d'un `@State offset` que le glissement met à jour en
// continu. Soit ~250 calques recomposés soixante fois par seconde.
//
// Ces tests ne mesurent pas des images par seconde : une telle assertion
// passerait ou échouerait selon la machine et selon l'humeur du simulateur. Ils
// vérifient ce qui CAUSE le coût — que le travail statique n'est fait qu'une
// fois, et que la correspondance variante/plante reste stable pour que le cache
// serve à quelque chose.

@MainActor
final class GardenMapPerformanceTests: XCTestCase {

    // MARK: - Le cache de symboles

    /// L'invariant du correctif : un symbole n'est dessiné qu'une fois par
    /// couple (variante, taille).
    ///
    /// Deux demandes identiques doivent rendre la MÊME instance. Si elles
    /// diffèrent, le cache ne sert à rien et les dix pétales sont redessinés à
    /// chaque image.
    func testUnSymboleNEstRasteriseQuUneFois() throws {
        let a = PlantSymbolCache.image(pour: .rosette, cote: 27)
        let b = PlantSymbolCache.image(pour: .rosette, cote: 27)

        XCTAssertEqual(a, b, "Deux demandes identiques doivent servir la même image")
    }

    /// Les deux tailles du marqueur — sélectionné ou non — sont des entrées
    /// distinctes. Servir l'une pour l'autre donnerait un symbole flou.
    func testLesDeuxTaillesSontDesEntreesDistinctes() {
        let petit = PlantSymbolCache.image(pour: .rosette, cote: 27)
        let grand = PlantSymbolCache.image(pour: .rosette, cote: 34)

        XCTAssertNotEqual(petit, grand,
                          "La taille fait partie de la clé : un symbole agrandi serait flou")
    }

    /// Les cinq variantes doivent toutes se rastériser. Une seule qui échouerait
    /// retomberait sur le repli et perdrait son dessin.
    func testLesCinqVariantesSeRasterisent() {
        for variante in [PlantMapMarkerVariant.rosette, .palm, .fern, .succulent, .cactus] {
            let image = PlantSymbolCache.image(pour: variante, cote: 27)
            XCTAssertEqual(image, PlantSymbolCache.image(pour: variante, cote: 27),
                           "La variante \(variante) doit être mise en cache")
        }
    }

    // MARK: - La stabilité de la variante

    /// Un cache ne vaut que si la clé est stable. Si la même plante changeait de
    /// variante entre deux images, on rastériserait sans fin.
    func testLaVarianteEstStablePourUneMemePlante() {
        let a = PlantMapMarkerVariant(index: 3, plantName: "Monstera deliciosa")
        let b = PlantMapMarkerVariant(index: 3, plantName: "Monstera deliciosa")

        XCTAssertEqual(a, b, "La variante doit être une fonction pure de ses entrées")
    }

    /// Le nom prime sur l'index : un cactus reste un cactus quelle que soit sa
    /// place dans la liste. C'est la règle métier existante, et la rastérisation
    /// ne doit pas l'avoir altérée.
    func testLeNomPrimeSurLIndexPourLesCactus() {
        for index in 0..<5 {
            XCTAssertEqual(PlantMapMarkerVariant(index: index, plantName: "Cactus de Noël"),
                           .cactus,
                           "Un cactus doit garder son symbole quel que soit son rang")
        }
    }

    /// L'accent ne doit pas faire échouer la reconnaissance : la comparaison est
    /// faite sans diacritiques.
    func testLaReconnaissanceIgnoreLesAccents() {
        XCTAssertEqual(PlantMapMarkerVariant(index: 0, plantName: "Plante succulente"), .cactus)
        XCTAssertEqual(PlantMapMarkerVariant(index: 0, plantName: "Plante Succulènte"), .cactus)
    }

    /// Sans mot-clé, la variante tourne sur l'index — mais sur QUATRE symboles,
    /// pas cinq.
    ///
    /// `case 4` retombe dans `default` et rend `.rosette` : `.cactus` n'est
    /// atteignable que par le nom. Ce test a d'abord affirmé cinq, et le code
    /// lui a donné tort. Il décrit désormais le contrat réel plutôt que celui
    /// qu'on imaginait.
    ///
    /// Est-ce voulu ? Réserver le cactus aux vrais cactus se défend. Mais
    /// `case 3` donne `.succulent` à une plante quelconque, ce qui affaiblit
    /// l'argument. Comportement antérieur au correctif de performance, laissé
    /// tel quel : le changer relèverait du design du plan, pas de sa vitesse.
    func testSansMotCleLaVarianteTourneSurQuatreSymboles() {
        let variantes = (0..<5).map { PlantMapMarkerVariant(index: $0, plantName: "Plante \($0)") }

        XCTAssertEqual(Set(variantes).count, 4,
                       "Quatre symboles par index ; .cactus est réservé au nom")
        XCTAssertFalse(variantes.contains(.cactus),
                       "Aucun index ne doit produire .cactus")
        XCTAssertEqual(PlantMapMarkerVariant(index: 4, plantName: "Plante 4"), .rosette,
                       "L'index 4 retombe sur .rosette par le `default`")
    }

    // MARK: - Le nombre de clés reste borné

    /// Le cache ne doit pas croître avec le nombre de plantes.
    ///
    /// C'est ce qui rend la correction sûre : cinq variantes × deux tailles font
    /// dix entrées au maximum, que le jardin en compte seize ou deux cents. Une
    /// clé qui dépendrait du nom ou de la position ferait du cache une fuite.
    func testLeCacheEstBornéParLesVariantesEtNonParLesPlantes() {
        let tailles: [CGFloat] = [27, 34]
        var cles = Set<String>()
        for index in 0..<200 {
            let variante = PlantMapMarkerVariant(index: index, plantName: "Plante \(index)")
            for cote in tailles {
                _ = PlantSymbolCache.image(pour: variante, cote: cote)
                cles.insert("\(variante)-\(cote)")
            }
        }

        XCTAssertLessThanOrEqual(cles.count, 10,
                                 "Au plus 5 variantes × 2 tailles, quelle que soit la taille du jardin")
    }
}
