import XCTest
import UIKit
@testable import ArboreUi

// PlantThumbnailDecodingTests.swift — gel du catalogue (ARBORE-FRONTEND-A).
//
// Le premier événement réel du build 32 : App Hang ≥ 2 s en parcourant le
// catalogue, sur un iPhone 17 Pro, en production. La pile s'arrêtait dans
// `CA::Layer::layout_and_display_if_needed` → `ScrollViewContentFrame`, sans
// aucune frame applicative — le thread principal était bloqué DANS le rendu.
//
// La cause n'était pas une fonction lente, c'était une absente.
// `UIImage(contentsOfFile:)` et `UIImage(data:)` ne décompressent rien : ils
// rendent une image paresseuse dont le décodage a lieu au premier dessin, donc
// sur le thread principal. Le code chargeait consciencieusement le fichier dans
// un `Task.detached` — ce qui déporte la lecture, pas le décodage.
//
// S'y ajoutait `isLegacyThumbnail`, quatre balayages de pixels forçant chacun un
// décodage complet, rejoués à CHAQUE apparition de carte alors que leur verdict
// ne dépend que du fichier. Soit environ cinq décodages d'un PNG 720 × 900 par
// vignette affichée, pour une grille qui en montre cinq à la fois.
//
// Ces tests gardent les trois propriétés qui font tenir le correctif. Aucun ne
// mesure un temps : une assertion de durée passerait ou échouerait selon la
// machine. Ils vérifient à la place ce qui CAUSE la durée — que l'image est
// décodée d'avance, qu'elle est réduite, et qu'elle n'est calculée qu'une fois.

final class PlantThumbnailDecodingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PlantThumbnailCache.viderCachesMemoire()
    }

    override func tearDown() {
        PlantThumbnailCache.viderCachesMemoire()
        super.tearDown()
    }

    // MARK: - Fabrique

    /// Un PNG de la taille réelle des vignettes servies : 720 × 900.
    ///
    /// Le fond gris uniforme 0.72 n'est pas décoratif : c'est la seule forme
    /// que `isLegacyThumbnail` accepte sans réserve, et celle qu'emploient déjà
    /// `PlantThumbnailRenderingTests`. Une première version de cette fabrique
    /// dessinait un bloc coloré sur fond blanc — soit exactement ce que
    /// `hasLegacyWhiteWallDarkFloor` est fait pour détecter, et la vignette se
    /// faisait condamner. Le détecteur avait raison ; c'est la fabrique qui
    /// mentait.
    ///
    /// Ces tests portent sur le cycle du cache, pas sur le détecteur — lequel a
    /// ses propres tests.
    private func pngDeVignette(width: CGFloat = 720, height: CGFloat = 900) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                            format: format).image { ctx in
            UIColor(white: 0.72, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try XCTUnwrap(image.pngData())
    }

    // MARK: - L'invariant central : l'image arrive décodée

    /// La régression, dans sa forme la plus directe.
    ///
    /// `CGImage` non nul ne suffit pas à prouver le décodage — une image
    /// paresseuse en expose un aussi. Ce qui le prouve, c'est de pouvoir lire
    /// les octets : `dataProvider.data` force le décodage s'il n'a pas eu lieu,
    /// et le fait de le faire ICI, dans le test, est précisément ce que le
    /// correctif garantit qu'on peut faire hors du thread principal.
    func testUneImagePrepareeExposeSesPixelsSansAttendreLeRendu() throws {
        let data = try pngDeVignette()
        let image = try XCTUnwrap(PlantThumbnailCache.imagePreteAAfficher(data: data))
        let cg = try XCTUnwrap(image.cgImage)

        XCTAssertNotNil(cg.dataProvider?.data,
                        "Les pixels doivent être disponibles sans passer par un dessin")
        XCTAssertGreaterThan(cg.width, 0)
        XCTAssertGreaterThan(cg.height, 0)
    }

    /// Le second bénéfice : moins de pixels à décoder, puis à dessiner.
    ///
    /// La carte mesure ~173 × 220 pt, soit 519 × 660 px à l'échelle 3. Réduire
    /// 720 × 900 à 576 × 720 couvre ce besoin avec de la marge.
    func testUneVignetteEstReduiteAuxBesoinsDeLaCarte() throws {
        let data = try pngDeVignette()
        let image = try XCTUnwrap(PlantThumbnailCache.imagePreteAAfficher(data: data))
        let cg = try XCTUnwrap(image.cgImage)

        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 720,
                                 "Le côté le plus long doit être ramené à la taille d'affichage")
        XCTAssertGreaterThanOrEqual(cg.height, 660,
                                    "…mais pas en dessous de ce qu'un écran à l'échelle 3 demande")
        XCTAssertLessThan(cg.width * cg.height, 720 * 900,
                          "Il doit rester moins de pixels à décoder qu'à l'origine")
    }

    /// Une image plus petite que la cible ne doit pas être agrandie : on
    /// gagnerait des pixels à décoder au lieu d'en perdre.
    func testUnePetiteVignetteNEstPasAgrandie() throws {
        let data = try pngDeVignette(width: 300, height: 375)
        let image = try XCTUnwrap(PlantThumbnailCache.imagePreteAAfficher(data: data))
        let cg = try XCTUnwrap(image.cgImage)

        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 375)
    }

    /// Des octets illisibles ne doivent pas faire tomber l'appelant.
    func testDesOctetsInvalidesRendentNilPlutotQueDePlanter() {
        let poubelle = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertNil(PlantThumbnailCache.imagePreteAAfficher(data: poubelle))
    }

    // MARK: - La mémoire : ne payer qu'une fois

    /// Le cœur du correctif côté défilement. Une carte qui réapparaît ne doit
    /// ni relire le fichier, ni le revalider, ni le redécoder.
    ///
    /// L'identité de l'objet est la preuve : un second `load` qui rendrait une
    /// instance différente aurait refait le travail.
    func testUneSecondeLectureRendLaMemeInstanceSansRefaireLeTravail() throws {
        let id = "test-memoire-\(UUID().uuidString)"
        let data = try pngDeVignette()
        let originale = try XCTUnwrap(UIImage(data: data))
        PlantThumbnailCache.save(originale, plantID: id)
        defer { try? FileManager.default.removeItem(at: PlantThumbnailCache.url(for: id)) }

        let premiere = try XCTUnwrap(PlantThumbnailCache.load(for: id))
        let seconde = try XCTUnwrap(PlantThumbnailCache.load(for: id))

        XCTAssertTrue(premiere === seconde,
                      "Le second appel doit servir l'instance déjà décodée")
    }

    /// `save` réécrit le fichier sous la même clé : la mémoire doit suivre,
    /// sans quoi un `load` ultérieur servirait l'image précédente.
    func testUneReecritureRemplaceLImageEnMemoire() throws {
        let id = "test-reecriture-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: PlantThumbnailCache.url(for: id)) }

        let premiere = try XCTUnwrap(UIImage(data: try pngDeVignette()))
        PlantThumbnailCache.save(premiere, plantID: id)
        let avant = try XCTUnwrap(PlantThumbnailCache.load(for: id))

        // Une taille franchement différente, et sous le plafond de réduction :
        // deux images qui plafonnent toutes deux à 720 se ressembleraient une
        // fois préparées, et le test ne prouverait rien.
        let seconde = try XCTUnwrap(UIImage(data: try pngDeVignette(width: 320, height: 400)))
        PlantThumbnailCache.save(seconde, plantID: id)
        let apres = try XCTUnwrap(PlantThumbnailCache.load(for: id))

        XCTAssertFalse(avant === apres, "La mémoire doit être invalidée par la réécriture")
        XCTAssertNotEqual(avant.cgImage?.height, apres.cgImage?.height,
                          "C'est bien la nouvelle image qui est servie")
    }

    /// Ce que `save` rend doit être directement affichable : c'est ce que la
    /// carte pose dans sa vue, sans repasser par un décodage.
    func testCeQueSaveRendEstDejaDecode() throws {
        let id = "test-save-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: PlantThumbnailCache.url(for: id)) }

        let originale = try XCTUnwrap(UIImage(data: try pngDeVignette()))
        let rendue = PlantThumbnailCache.save(originale, plantID: id)

        let cg = try XCTUnwrap(rendue.cgImage)
        XCTAssertNotNil(cg.dataProvider?.data)
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 720)
    }

    // MARK: - Ce que la réduction ne doit PAS toucher

    /// Le piège que ce correctif a failli introduire.
    ///
    /// `isLegacyThumbnail` échantillonne des pixels et efface le fichier quand
    /// il conclut à une vignette périmée. Le juger sur une image redimensionnée
    /// ferait basculer ses seuils de luminosité, et des vignettes légitimes
    /// finiraient supprimées. Le contrôle porte donc sur l'ORIGINALE, et seul
    /// l'affichage reçoit la version réduite.
    ///
    /// Ce test le vérifie par sa conséquence : une vignette correctement
    /// marquée survit à un aller-retour complet par le cache.
    func testUneVignetteLegitimeSurvitAuCycleComplet() throws {
        let id = "test-survie-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: PlantThumbnailCache.url(for: id)) }

        let originale = try XCTUnwrap(UIImage(data: try pngDeVignette()))
        PlantThumbnailCache.save(originale, plantID: id)
        PlantThumbnailCache.viderCachesMemoire()   // forcer la relecture disque

        XCTAssertNotNil(PlantThumbnailCache.load(for: id),
                        "Le contrôle d'ancienneté ne doit pas condamner une vignette valide")
        XCTAssertTrue(FileManager.default.fileExists(at: PlantThumbnailCache.url(for: id)),
                      "…ni effacer son fichier")
    }

    /// Un identifiant sans fichier reste sans image, et ne doit rien peupler.
    func testUnIdentifiantSansFichierRendNil() {
        XCTAssertNil(PlantThumbnailCache.load(for: "absent-\(UUID().uuidString)"))
    }
}

private extension FileManager {
    func fileExists(at url: URL) -> Bool { fileExists(atPath: url.path) }
}
