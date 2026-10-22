import XCTest
@testable import ArboreUi

// PlantPotCompositionTests — issues #609, #623, #280, #294.
//
// Deux familles de défauts, de gravités très différentes.
//
// Ne PAS poser de pot **dégrade** : la plante recoupée s'affiche nue, c'est
// laid mais visible, et ça se répare. Poser un pot **mal placé** trompe : il
// traverse la plante ou flotte, et l'utilisateur l'attribue à un bug d'AR, pas
// à une donnée. Ces tests insistent donc sur les cas où il faut REFUSER.
//
// La troisième famille est la régression silencieuse : une plante historique,
// dont le maillage contient déjà son pot, ne doit rien voir changer. Et une
// fiche sans empreinte doit garder son cache au lieu de le perdre.

final class PlantPotCompositionTests: XCTestCase {

    // Socle relevé par l'atelier sur Aglaonema_Mix, en unités du modèle.
    private func socleReel() -> PlantPotBase {
        PlantPotBase(x: 0.00432, y: -0.10521, z: -0.07449, radius: 0.16146,
                     groundY: -0.19691, plantHeight: 0.64856)
    }

    private func pot(_ nom: String, rebord: Double, defaut: Bool = false) -> Pot {
        Pot(id: nom, name: nom, modelURL: "\(nom).usdz",
            rimRadius: rebord, height: 0.1, isDefault: defaut)
    }

    // MARK: - Pose

    func testPose_ValeursRelevees() throws {
        let p = pot("cachepot_pieds", rebord: 0.058654)
        let pose = try XCTUnwrap(PlantPotComposer.placement(base: socleReel(), pot: p))
        XCTAssertEqual(pose.scale, 0.16146 / 0.058654, accuracy: 1e-9)
        XCTAssertEqual(pose.x, 0.00432, accuracy: 1e-9)
        XCTAssertEqual(pose.y, -0.10521, accuracy: 1e-9,
                       "la lèvre du pot s'aligne sur le socle, pas sur le sol")
        XCTAssertEqual(pose.z, -0.07449, accuracy: 1e-9)
    }

    // Le serveur applique déjà ce refus. Celui-ci le tient AUSSI pour un pot
    // choisi en local, qui ne repasse jamais par lui.
    func testPose_RefuseCeQuiNaPasDeSens() {
        let p = pot("normal", rebord: 0.05)
        XCTAssertNil(PlantPotComposer.placement(base: nil, pot: p), "socle absent")
        XCTAssertNil(PlantPotComposer.placement(base: socleReel(), pot: nil), "pot absent")
        XCTAssertNil(PlantPotComposer.placement(base: socleReel(), pot: pot("plat", rebord: 0)),
                     "rebord nul")
        XCTAssertNil(PlantPotComposer.placement(base: socleReel(), pot: pot("neg", rebord: -0.05)),
                     "rebord négatif")
        XCTAssertNil(PlantPotComposer.placement(
            base: PlantPotBase(x: 0, y: 0, z: 0, radius: 0), pot: p), "socle de rayon nul")
    }

    func testPose_RefuseLesValeursNonFinies() {
        let p = pot("normal", rebord: 0.05)
        XCTAssertNil(PlantPotComposer.placement(
            base: PlantPotBase(x: 0, y: 0, z: 0, radius: .infinity), pot: p))
        XCTAssertNil(PlantPotComposer.placement(
            base: PlantPotBase(x: 0, y: 0, z: 0, radius: .nan), pot: p))
    }

    // MARK: - Choix du pot

    func testChoix_LeDemandeLEmporte() {
        let pots = [pot("a", rebord: 0.05, defaut: true), pot("b", rebord: 0.06)]
        XCTAssertEqual(PlantPotComposer.pot(parmi: pots, choisi: "b")?.id, "b")
    }

    func testChoix_SansDemandeLeDefaut() {
        let pots = [pot("a", rebord: 0.05), pot("b", rebord: 0.06, defaut: true)]
        XCTAssertEqual(PlantPotComposer.pot(parmi: pots, choisi: nil)?.id, "b")
    }

    // Le choix est persisté dans le jardin de l'utilisateur (#280). Si ce pot
    // quitte la bibliothèque, la scène doit continuer à s'afficher plutôt que
    // de perdre sa plante.
    func testChoix_PotDisparuRetombeSurLeDefaut() {
        let pots = [pot("a", rebord: 0.05), pot("b", rebord: 0.06, defaut: true)]
        XCTAssertEqual(PlantPotComposer.pot(parmi: pots, choisi: "efface")?.id, "b")
    }

    func testChoix_SansDefautDeclareLePremier() {
        let pots = [pot("a", rebord: 0.05), pot("b", rebord: 0.06)]
        XCTAssertEqual(PlantPotComposer.pot(parmi: pots, choisi: nil)?.id, "a")
    }

    func testChoix_BibliothequeVide() {
        XCTAssertNil(PlantPotComposer.pot(parmi: [], choisi: nil))
        XCTAssertNil(PlantPotComposer.pot(parmi: [], choisi: "a"))
    }

    // MARK: - Décodage

    private func plante(_ corps: String) throws -> Plant {
        let json = """
        {"id":"p","name":"Test","type":"interieur","description":"d",
         "modelURL":"X.usdz","translations":{}\(corps)}
        """
        return try JSONDecoder().decode(Plant.self, from: Data(json.utf8))
    }

    func testDecodage_FicheRecoupeeComplete() throws {
        let p = try plante("""
        ,"potless":true,"heightMeters":0.241,
         "potBase":{"x":0.00432,"y":-0.10521,"z":-0.07449,"radius":0.16146,"groundY":-0.19691},
         "versions":{"model":"62d4ee94","thumbnail":"e085270c"},
         "pot":{"id":"abc","name":"cachepot","modelURL":"cachepot.usdz",
                "rimRadius":0.058654,"height":0.1,"default":true,"version":"9d9f265d"}
        """)
        XCTAssertTrue(p.attendUnPot)
        XCTAssertEqual(p.heightMeters, 0.241)
        XCTAssertEqual(p.potBase?.radius, 0.16146)
        XCTAssertEqual(p.potBase?.groundY, -0.19691)
        XCTAssertNil(p.potBase?.plantHeight, "non mesurée sur la plupart des fiches")
        XCTAssertEqual(p.versions?.model, "62d4ee94")
        XCTAssertNil(p.versions?.modelHeavy, "une plante recoupée n'a pas de LOD lourd")
        XCTAssertEqual(p.pot?.rimRadius, 0.058654)
        XCTAssertTrue(p.pot?.isDefault == true, "`default` est un mot réservé, la clé doit être mappée")
    }

    // La régression qui compte : une fiche d'avant ne doit rien voir changer.
    func testDecodage_FicheHistoriqueInchangee() throws {
        let p = try plante("")
        XCTAssertFalse(p.attendUnPot)
        XCTAssertNil(p.potBase)
        XCTAssertNil(p.heightMeters)
        XCTAssertNil(p.versions)
        XCTAssertNil(p.pot)
        XCTAssertEqual(p.modelURL, "X.usdz")
    }

    func testDecodage_PotlessFauxEstHistorique() throws {
        XCTAssertFalse(try plante(",\"potless\":false").attendUnPot)
    }

    // Un socle amputé ne doit pas faire échouer la fiche entière : la plante
    // disparaîtrait du catalogue, et on attribuerait ça au réseau (cf. #489).
    func testDecodage_SocleIncompletNeCassePasLaFiche() throws {
        let p = try plante(",\"potBase\":{\"radius\":0.16}")
        XCTAssertEqual(p.potBase?.radius, 0.16)
        XCTAssertEqual(p.potBase?.x, 0)
        // Un socle qui porte un rayon mais pas de position reste exploitable :
        // le pot se pose à l'origine du modèle. Seul un rayon manquant ou nul
        // rend la pose impossible.
        let pose = try XCTUnwrap(
            PlantPotComposer.placement(base: p.potBase, pot: pot("p", rebord: 0.05)))
        XCTAssertEqual(pose.scale, 0.16 / 0.05, accuracy: 1e-9)
        XCTAssertEqual(pose.x, 0)
        XCTAssertEqual(pose.y, 0)
        XCTAssertEqual(pose.z, 0)
    }

    // MARK: - L'invariant : une plante recoupée a toujours un pot

    // La question qui a motivé ces tests : « partout où les plantes sont
    // appelées, si sans_pot alors on lie le pot — c'est bien respecté ? »
    //
    // L'invariant doit tenir en UN seul endroit, sinon chaque nouvel appelant
    // doit y penser, et un jour l'un d'eux n'y pensera pas.

    func testInvariant_UneRecoupeeRecoitSonPotSansBibliotheque() throws {
        let p = try plante("""
        ,"potless":true,"potBase":{"radius":0.16146,"x":0,"y":-0.1,"z":0},
         "pot":{"id":"abc","name":"cachepot","modelURL":"c.usdz",
                "rimRadius":0.058654,"height":0.1,"default":true}
        """)
        let lie = try XCTUnwrap(p.potEtPose(),
                                "le pot servi avec la fiche doit suffire : sans lui, la plante s'afficherait nue le temps d'un aller-retour")
        XCTAssertEqual(lie.pot.id, "abc")
        XCTAssertEqual(lie.pose.scale, 0.16146 / 0.058654, accuracy: 1e-9)
    }

    func testInvariant_UnePlanteHistoriqueNenRecoitAucun() throws {
        let p = try plante("")
        XCTAssertNil(p.potEtPose(bibliotheque: [pot("a", rebord: 0.05, defaut: true)]),
                     "son maillage porte déjà son pot ; un second s'y superposerait")
    }

    // Une recoupée sans socle n'a pas de pose calculable : lui lier un pot
    // reviendrait à le poser au hasard.
    func testInvariant_UneRecoupeeSansSocleNenRecoitPas() throws {
        let p = try plante(",\"potless\":true")
        XCTAssertNil(p.potEtPose(bibliotheque: [pot("a", rebord: 0.05, defaut: true)]))
    }

    // Le choix de l'utilisateur, persisté dans son jardin, l'emporte sur le
    // pot que le serveur avait servi.
    func testInvariant_LeChoixLocalLEmporteSurLePotServi() throws {
        let p = try plante("""
        ,"potless":true,"potBase":{"radius":0.16,"x":0,"y":0,"z":0},
         "pot":{"id":"servi","name":"servi","modelURL":"s.usdz",
                "rimRadius":0.05,"height":0.1,"default":true}
        """)
        let autre = pot("choisi", rebord: 0.08)
        let lie = try XCTUnwrap(p.potEtPose(choisi: "choisi", bibliotheque: [autre]))
        XCTAssertEqual(lie.pot.id, "choisi")
        XCTAssertEqual(lie.pose.scale, 0.16 / 0.08, accuracy: 1e-9)
    }

    // Un catalogue entier doit sortir cohérent : chaque recoupée posable avec
    // son pot, chaque historique sans.
    func testInvariant_SurUnCatalogueEntier() throws {
        let recoupee = """
        ,"potless":true,"potBase":{"radius":0.16,"x":0,"y":0,"z":0},
         "pot":{"id":"p","name":"p","modelURL":"p.usdz",
                "rimRadius":0.05,"height":0.1,"default":true}
        """
        let catalogue = [try plante(recoupee), try plante(""),
                         try plante(recoupee), try plante(",\"potless\":true")]
        let lies = catalogue.map { $0.potEtPose() != nil }
        XCTAssertEqual(lies, [true, false, true, false])
    }

    // MARK: - Un jardin enregistré se rouvre sans réseau

    // Le pot CHOISI ne se retrouve que dans la bibliothèque, et la pose se
    // calcule depuis `potBase`, qui vit dans le catalogue. Ni l'un ni l'autre
    // n'est disponible hors ligne : le jardin doit donc porter sa propre copie,
    // exactement comme il porte déjà `modelURLString` et `hasHeavy`.

    func testJardin_LePotPersisteAvecSaPose() throws {
        let p = pot("cachepot", rebord: 0.058654, defaut: true)
        let pose = try XCTUnwrap(PlantPotComposer.placement(base: socleReel(), pot: p))
        let enregistre = PersistedPot(pot: p, pose: pose)

        XCTAssertEqual(enregistre.potID, "cachepot")
        XCTAssertEqual(enregistre.modelURLString, "cachepot.usdz")
        let relue = try XCTUnwrap(enregistre.pose)
        XCTAssertEqual(relue.scale, pose.scale, accuracy: 1e-6)
        XCTAssertEqual(relue.y, pose.y, accuracy: 1e-6,
                       "la lèvre doit se retrouver où elle était")
    }

    func testJardin_SurvitAuCodageJSON() throws {
        let p = pot("cachepot", rebord: 0.05)
        let pose = try XCTUnwrap(PlantPotComposer.placement(base: socleReel(), pot: p))
        let brut = try JSONEncoder().encode(PersistedPot(pot: p, pose: pose))
        let relu = try JSONDecoder().decode(PersistedPot.self, from: brut)
        XCTAssertEqual(relu, PersistedPot(pot: p, pose: pose))
    }

    // Une sauvegarde d'avant n'a pas la clé : elle doit décoder, pas échouer.
    func testJardin_UneSauvegardeDAvantDecodeSansPot() throws {
        let json = """
        {"plantID":"p","plantName":"n","modelURLString":"m.usdz",
         "position":[0,0,0],"rotation":[0,0,0,0],"scale":[1,1,1],
         "transform":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}
        """
        let plante = try JSONDecoder().decode(PersistedPlant.self, from: Data(json.utf8))
        XCTAssertNil(plante.pot)
        XCTAssertEqual(plante.modelURLString, "m.usdz")
    }

    // Un enregistrement amputé ne doit pas produire une pose absurde.
    func testJardin_EnregistrementAmputeNeDonneAucunePose() {
        XCTAssertNil(PersistedPot(potID: "p", modelURLString: "p.usdz",
                                  scale: 1, offset: [0, 0]).pose, "offset incomplet")
        XCTAssertNil(PersistedPot(potID: "p", modelURLString: "p.usdz",
                                  scale: 0, offset: [0, 0, 0]).pose, "échelle nulle")
        XCTAssertNil(PersistedPot(potID: "p", modelURLString: "p.usdz",
                                  scale: .infinity, offset: [0, 0, 0]).pose, "échelle non finie")
    }

    // MARK: - Empreintes et cache

    func testEmpreinte_ParNiveauDeDetail() throws {
        let p = try plante(",\"versions\":{\"model\":\"aaaa1111\",\"modelHeavy\":\"bbbb2222\"}")
        XCTAssertEqual(p.empreinte(pour: .light), "aaaa1111")
        XCTAssertEqual(p.empreinte(pour: .heavy), "bbbb2222")
    }

    func testEmpreinte_AbsenteLaisseLeCacheTelQuel() throws {
        let p = try plante("")
        XCTAssertNil(p.empreinte(pour: .light))
        XCTAssertEqual(nomEnCache(fichier: "Monstera.usdz", version: nil), "Monstera.usdz",
                       "sans empreinte, le nom reste celui d'avant : la fiche garde son cache")
    }

    func testNomEnCache_LEmpreinteEntreAvantLExtension() {
        XCTAssertEqual(nomEnCache(fichier: "Monstera.usdz", version: "62d4ee94"),
                       "Monstera_62d4ee94.usdz")
        XCTAssertEqual(nomEnCache(fichier: "sans_extension", version: "abcd1234"),
                       "sans_extension_abcd1234")
        XCTAssertEqual(nomEnCache(fichier: "Monstera.usdz", version: ""), "Monstera.usdz",
                       "une empreinte vide vaut une absence")
    }

    // Deux contenus différents ne doivent jamais partager une entrée de cache :
    // c'est tout l'objet de #294.
    func testNomEnCache_DeuxContenusDeuxFichiers() {
        XCTAssertNotEqual(nomEnCache(fichier: "M.usdz", version: "aaaa1111"),
                          nomEnCache(fichier: "M.usdz", version: "bbbb2222"))
    }

    func testURLDistante_PorteLeLodEtLEmpreinte() {
        XCTAssertEqual(
            ModelLOD.light.remoteURLString(base: "https://x", filename: "M.usdz", version: "ab12cd34"),
            "https://x/models/M.usdz?v=ab12cd34")
        XCTAssertEqual(
            ModelLOD.heavy.remoteURLString(base: "https://x", filename: "M.usdz", version: "ab12cd34"),
            "https://x/models/M.usdz?lod=heavy&v=ab12cd34")
        XCTAssertEqual(
            ModelLOD.heavy.remoteURLString(base: "https://x", filename: "M.usdz"),
            "https://x/models/M.usdz?lod=heavy",
            "sans empreinte, l'URL reste exactement celle d'avant")
        XCTAssertEqual(
            ModelLOD.light.remoteURLString(base: "https://x", filename: "M.usdz", version: ""),
            "https://x/models/M.usdz")
    }

    // MARK: - Purge unique

    func testPurge_NeSexecuteQuUneFois() async throws {
        let suite = "test.purge.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let premier = await ModelCacheManager.shared.purgerSiAnterieurAuxEmpreintes(defaults: defaults)
        XCTAssertGreaterThanOrEqual(premier, 0)
        let second = await ModelCacheManager.shared.purgerSiAnterieurAuxEmpreintes(defaults: defaults)
        XCTAssertEqual(second, 0,
                       "sans le drapeau, chaque lancement viderait le cache et retéléchargerait tout")
    }
}
