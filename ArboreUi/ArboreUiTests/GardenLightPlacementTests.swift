import XCTest
@testable import ArboreUi

// GardenLightPlacementTests — issue #795.
//
// Ces tests n'existaient pas parce que la décision de pose vivait dans une
// fonction imbriquée au milieu de `GardenARPlacementView`, et qu'on a conclu
// de là qu'elle demandait un appareil pour être vérifiée.
//
// C'était faux, et la distinction vaut d'être écrite : le RENDU dans une
// pièce réelle demande un iPhone, sa caméra et son LiDAR. La DÉCISION — quelle
// plante va où — est du calcul pur sur des nombres. Elle se précalcule, donc
// elle se teste.
//
// Ce qui reste hors de portée d'un test : savoir si « profondeur maximale »
// correspond vraiment au côté ensoleillé d'un salon. C'est une question sur le
// capteur et sur la pièce, pas sur le code.

final class GardenLightPlacementTests: XCTestCase {

    private let zone = GardenPlacementDepth(min: 0, mid: 2, max: 4, centroid: 2)

    // MARK: - Le besoin se lit sur la donnée, plus sur le nom

    /// LE test qui justifie l'extraction : un nom qui mentirait n'a plus
    /// aucun effet.
    ///
    /// Les 29 genres que l'ancien code appariait sont ici dans les noms, à
    /// l'envers de ce que dit la donnée. Un `Monstera` était classé « ombre »
    /// par son nom ; sa fiche dit 7 à 9 heures de soleil direct.
    func testUnNomQuiMentNeChangeRienAuBesoin() throws {
        let fauxOmbre = try plante(nom: "Monstera deliciosa pothos lierre", soleil: (7, 9))
        let fauxSoleil = try plante(nom: "Cactus agave yucca olivier", soleil: (0, 2))

        XCTAssertEqual(
            GardenLightPlacement.need(for: fauxOmbre), .fullSun,
            "7 à 9 h de soleil direct : plein soleil, quoi que dise le nom"
        )
        XCTAssertEqual(
            GardenLightPlacement.need(for: fauxSoleil), .shade,
            "0 à 2 h : ombre, quoi que dise le nom"
        )
    }

    func testLesTroisBesoinsSortentDesSeuilsPartages() throws {
        XCTAssertEqual(try plante(soleil: (6, 8)).besoin(), .fullSun, "6 h est le seuil, inclus")
        XCTAssertEqual(try plante(soleil: (0, 3)).besoin(), .shade, "3 h est le seuil, inclus")
        XCTAssertEqual(try plante(soleil: (4, 5)).besoin(), .partial, "entre les deux")
    }

    /// Sans fait, seul le `true` d'un drapeau informe.
    func testSansFaitSeulLeDrapeauLeveInforme() throws {
        XCTAssertEqual(try plante(drapeauSoleil: true).besoin(), .fullSun)
        XCTAssertEqual(try plante(drapeauOmbre: true).besoin(), .shade)
        XCTAssertEqual(
            try plante(drapeauSoleil: false, drapeauOmbre: false).besoin(), .partial,
            "deux drapeaux baissés ne disent rien : rang neutre"
        )
        XCTAssertEqual(try plante().besoin(), .partial, "aucune donnée : rang neutre")
    }

    // MARK: - L'ordre de pose

    /// Dans une pièce lumineuse, le plein soleil passe d'abord et prend les
    /// emplacements exposés. Dans une pièce sombre, l'ordre s'inverse.
    func testLOrdreSInverseSelonLaLuminositeDeLaPiece() throws {
        let soleil = try plante(nom: "soleil", soleil: (8, 10))
        let mi = try plante(nom: "mi-ombre", soleil: (4, 5))
        let ombre = try plante(nom: "ombre", soleil: (0, 2))
        let melange = [ombre, soleil, mi]

        XCTAssertEqual(
            GardenLightPlacement.ordered(melange, lux: 800).map(\.name),
            ["soleil", "mi-ombre", "ombre"],
            "pièce lumineuse : le plein soleil prend les places exposées"
        )
        XCTAssertEqual(
            GardenLightPlacement.ordered(melange, lux: 100).map(\.name),
            ["ombre", "mi-ombre", "soleil"],
            "pièce sombre : l'ombre prend les meilleures places"
        )
    }

    /// Deux poses du même jardin doivent donner le même ordre.
    ///
    /// Un tri instable sur des besoins égaux rendrait la disposition
    /// différente à chaque ouverture, sans que rien n'ait changé.
    func testLOrdreEstStablePourDesBesoinsEgaux() throws {
        let plantes = try (1...6).map { try plante(nom: "p\($0)", soleil: (4, 5)) }
        for _ in 0..<5 {
            XCTAssertEqual(
                GardenLightPlacement.ordered(plantes, lux: 800).map(\.name),
                ["p1", "p2", "p3", "p4", "p5", "p6"],
                "à besoin égal, l'ordre d'entrée est conservé"
            )
        }
    }

    // MARK: - La tranche de profondeur

    func testEnPieceLumineuseLeSoleilVaVersLExposeEtLOmbreVersLInterieur() {
        XCTAssertEqual(
            GardenLightPlacement.depthRange(for: .fullSun, lux: 800, depth: zone),
            2...4, "plein soleil : moitié exposée"
        )
        XCTAssertEqual(
            GardenLightPlacement.depthRange(for: .shade, lux: 800, depth: zone),
            0...2, "ombre : moitié intérieure"
        )
        XCTAssertEqual(
            GardenLightPlacement.depthRange(for: .partial, lux: 800, depth: zone),
            0...4, "mi-ombre : toute la zone"
        )
    }

    func testEnPieceSombreLeSoleilEstResserreAutourDuBarycentre() {
        XCTAssertEqual(
            GardenLightPlacement.depthRange(for: .fullSun, lux: 100, depth: zone),
            1.7...2.3,
            "pas de zone exposée à distribuer : au plus près du centre"
        )
        XCTAssertEqual(
            GardenLightPlacement.depthRange(for: .shade, lux: 100, depth: zone),
            0...4, "une pièce sombre convient à l'ombre : partout"
        )
    }

    /// Le barycentre d'une zone en L n'est pas au milieu de ses bornes.
    func testLeResserrementSuitLeBarycentreEtPasLeMilieu() {
        let enL = GardenPlacementDepth(min: 0, mid: 2, max: 4, centroid: 3.5)
        XCTAssertEqual(
            GardenLightPlacement.depthRange(for: .fullSun, lux: 100, depth: enL),
            3.2...3.8
        )
    }

    /// **Le cas qui planterait en production.**
    ///
    /// `ClosedRange` lève une exception fatale si sa borne basse dépasse la
    /// haute. Une zone plus étroite que le rayon de resserrement produit
    /// exactement ça, et le plantage arriverait au moment de poser un jardin.
    func testUneZonePlusEtroiteQueLeResserrementNeProduitPasDeTrancheVide() {
        let etroite = GardenPlacementDepth(min: 1.9, mid: 1.95, max: 2.0, centroid: 1.95)
        for besoin in GardenLightNeed.allCases {
            for lux in [50, 500, 5000] {
                let r = GardenLightPlacement.depthRange(for: besoin, lux: lux, depth: etroite)
                XCTAssertLessThanOrEqual(r.lowerBound, r.upperBound)
                XCTAssertGreaterThanOrEqual(r.lowerBound, etroite.min)
                XCTAssertLessThanOrEqual(r.upperBound, etroite.max)
            }
        }
    }

    /// Toute tranche reste dans la zone, pour toutes les combinaisons.
    func testToutesLesTranchesRestentDansLaZone() {
        for besoin in GardenLightNeed.allCases {
            for lux in [0, 499, 500, 501, 10_000] {
                let r = GardenLightPlacement.depthRange(for: besoin, lux: lux, depth: zone)
                XCTAssertGreaterThanOrEqual(r.lowerBound, zone.min, "\(besoin) à \(lux) lux")
                XCTAssertLessThanOrEqual(r.upperBound, zone.max, "\(besoin) à \(lux) lux")
            }
        }
    }

    /// Le seuil de luminosité est une frontière, pas une zone floue.
    func testLeSeuilDeLuminositeEstFranc() {
        let juste = PlantThresholds.Light.brightRoomLux
        XCTAssertEqual(
            GardenLightPlacement.depthRange(for: .fullSun, lux: juste, depth: zone),
            1.7...2.3, "à 500 lux exactement, la pièce n'est PAS lumineuse"
        )
        XCTAssertEqual(
            GardenLightPlacement.depthRange(for: .fullSun, lux: juste + 1, depth: zone),
            2...4, "un lux de plus, et elle l'est"
        )
    }

    // MARK: - Construction

    private func plante(
        nom: String = "Plante",
        soleil: (Double, Double)? = nil,
        drapeauSoleil: Bool? = nil,
        drapeauOmbre: Bool? = nil
    ) throws -> Plant {
        var json: [String: Any] = [
            "id": nom, "name": nom, "type": "Plant",
            "imageURLs": [], "description": "", "translations": [:]
        ]
        // `botanicalProfile` est à la RACINE du contrat de l'app. Le corpus de
        // recherche le niche sous `_meta`, mais c'est sa forme à lui : poser la
        // clé là ne décode rien, et l'absence est silencieuse.
        if let soleil {
            json["botanicalProfile"] = [
                "directSunHours": [
                    "minimum": soleil.0, "maximum": soleil.1, "unit": "hours"
                ]
            ]
        }
        if drapeauSoleil != nil || drapeauOmbre != nil {
            json["flags"] = [
                "fullSunTolerant": drapeauSoleil ?? false,
                "shadeTolerant": drapeauOmbre ?? false
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Plant.self, from: data)
    }
}

private extension Plant {
    func besoin() -> GardenLightNeed { GardenLightPlacement.need(for: self) }
}
