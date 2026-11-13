import XCTest
import SceneKit
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

// MARK: - Disque de terre (#623)
//
// Ce que ces cas protègent : l'atelier ne conserve la terre qu'à 75 % du rayon
// alors que le pot est posé à 100 %, et un anneau de paroi nue reste visible
// tout autour. Le disque le comble. Les deux erreurs opposées coûtent :
// trop large, il traverse la paroi ; trop étroit, il ne masque rien.

extension PlantPotCompositionTests {

    private var poseDeReference: PotPlacement {
        PotPlacement(scale: 2.4646, x: -0.02958, y: -0.20387, z: 0.02886)
    }

    func testDisqueTientDansLOuvertureDuPot() {
        // Mesuré sur le maillage servi : paroi intérieure à 0,0554 pour un
        // rebord extérieur à 0,0589. Le disque doit rester sous l'ouverture.
        let rayonExterieur = 0.14456
        guard let d = PlantPotComposer.disque(pose: poseDeReference,
                                              rayonExterieurPose: rayonExterieur,
                                              hauteurPose: 0.24646) else {
            return XCTFail("disque attendu")
        }
        let ouverture = rayonExterieur * PlantPotComposer.partOuverture
        XCTAssertLessThan(d.rayon, ouverture,
                          "le disque traverserait la paroi intérieure")
        XCTAssertGreaterThan(d.rayon, ouverture * 0.95,
                             "trop étroit : l'anneau nu resterait visible")
    }

    func testDisqueEstEnRetraitSousLaLevre() {
        guard let d = PlantPotComposer.disque(pose: poseDeReference,
                                              rayonExterieurPose: 0.14456,
                                              hauteurPose: 0.24646) else {
            return XCTFail("disque attendu")
        }
        XCTAssertLessThan(d.y, poseDeReference.y,
                          "au ras du rebord, le disque a l'air de flotter")
        XCTAssertGreaterThan(d.y, poseDeReference.y - 0.24646 * 0.25,
                             "trop bas, il décolle de la terre de la plante")
    }

    func testDisqueSuitLeCentreDuSocle() {
        guard let d = PlantPotComposer.disque(pose: poseDeReference,
                                              rayonExterieurPose: 0.14456,
                                              hauteurPose: 0.24646) else {
            return XCTFail("disque attendu")
        }
        XCTAssertEqual(d.x, poseDeReference.x, accuracy: 1e-9)
        XCTAssertEqual(d.z, poseDeReference.z, accuracy: 1e-9)
    }

    func testPasDeDisqueSansPose() {
        XCTAssertNil(PlantPotComposer.disque(pose: nil,
                                             rayonExterieurPose: 0.14456,
                                             hauteurPose: 0.24646))
    }

    func testPasDeDisqueSurDesDimensionsAberrantes() {
        // Un maillage illisible rendrait des bornes nulles ou infinies. Mieux
        // vaut un anneau nu qu'un disque au hasard, qu'on prendrait pour un bug.
        for (r, h) in [(0.0, 0.24646), (0.14456, 0.0), (-1.0, 0.2),
                       (Double.nan, 0.2), (0.14, Double.infinity)] {
            XCTAssertNil(PlantPotComposer.disque(pose: poseDeReference,
                                                 rayonExterieurPose: r,
                                                 hauteurPose: h),
                         "accepté à tort pour rayon=\(r) hauteur=\(h)")
        }
    }
}

// MARK: - Le pot survit à l'enregistrement (#795)
//
// Ce que ces cas protègent : un jardin rouvert revenait avec ses plantes mais
// SANS leurs pots. Deux endroits perdaient la même donnée, et pour la même
// raison — `PersistedPlant.init` accepte `pot:` avec une valeur par défaut,
// donc l'oublier au point d'appel ne tire pas un mot au compilateur :
//
//   - la capture d'état ne donnait jamais `pot:` ;
//   - la migration de recentrage reconstruit chaque plante champ par champ et
//     omettait `pot` ET `heightMeters`.
//
// Ces cas vérifient donc l'aller-retour COMPLET scène → disque → scène, pas
// l'existence du champ : encoder puis décoder un `PersistedPot` passait déjà
// avant le correctif, et ne prouvait rien.

extension PlantPotCompositionTests {

    private func transformMonde(x: Float, y: Float, z: Float) -> [Float] {
        var t = [Float](repeating: 0, count: 16)
        t[0] = 1; t[5] = 1; t[10] = 1; t[15] = 1
        t[12] = x; t[13] = y; t[14] = z
        return t
    }

    private func potEnregistre() throws -> PersistedPot {
        let p = pot("cachepot_pieds", rebord: 0.058654, defaut: true)
        let pose = try XCTUnwrap(PlantPotComposer.placement(base: socleReel(), pot: p))
        return PersistedPot(pot: p, pose: pose)
    }

    /// Le cas qui décide : un pot posé dans la scène doit se retrouver dans le
    /// jardin rechargé. On part du NŒUD — ce que la capture lit réellement —
    /// et on va jusqu'au JSON relu.
    func testEnregistrement_UnPotDansLaSceneSeRetrouveAuRechargement() throws {
        let attendu = try potEnregistre()

        // 1. la scène : le pot est porté par le nœud de la plante, comme le
        //    sont déjà sa hauteur mesurée et son ancre de surface.
        let noeud = SCNNode()
        noeud.arborePot = attendu
        noeud.arboreHeightMeters = 0.64856
        noeud.arborePlacementMode = "floor"

        // 2. la capture d'état, telle que la sauvegarde l'exécute.
        let capturee = PersistedPlant(
            noeud: noeud,
            plantID: "aglaonema_mix",
            plantName: "Aglaonema Mix",
            modelURLString: "Aglaonema_Mix.usdz",
            position: [1.2, 0, -0.7],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            transform: transformMonde(x: 1.2, y: 0, z: -0.7),
            upAxis: "Y",
            surfaceType: "floor",
            surfaceHeight: 0)

        // 3. le disque, puis la relecture — migration de lecture incluse.
        let brut = try JSONEncoder().encode(
            PersistedARScene(savedAt: Date(), plants: [capturee]))
        let relue = try JSONDecoder().decode(PersistedARScene.self, from: brut)
            .normalizedToWorldFrame()

        let plante = try XCTUnwrap(relue.plants.first)
        let relu = try XCTUnwrap(plante.pot,
                                 "le pot a été perdu entre la scène et le disque")
        XCTAssertEqual(relu, attendu)
        let pose = try XCTUnwrap(relu.pose)
        XCTAssertEqual(pose.scale, 0.16146 / 0.058654, accuracy: 1e-6,
                       "le pot doit revenir à l'échelle où il a été posé")
        XCTAssertEqual(plante.heightMeters, 0.64856,
                       "la hauteur mesurée voyage par le même chemin")
    }

    /// Même sauvegarde corrigée, toute sauvegarde passant par la migration de
    /// recentrage reperdrait son pot : elle reconstruit chaque plante.
    func testMigration_DeRecentrageConserveLePotEtLaHauteur() throws {
        let attendu = try potEnregistre()

        // Jardin legacy : `position` est shiftée du centroïde de la bordure,
        // `transform` ne l'est pas. L'écart déclenche la migration.
        let legacy = PersistedPlant(
            plantID: "aglaonema_mix",
            plantName: "Aglaonema Mix",
            modelURLString: "Aglaonema_Mix.usdz",
            position: [0, 0, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
            transform: transformMonde(x: 2.5, y: 0, z: -1.5),
            upAxis: "Y",
            surfaceType: "floor",
            surfaceHeight: 0,
            placementMode: "floor",
            surfaceAnchor: nil,
            hasHeavy: true,
            heightMeters: 0.64856,
            pot: attendu)

        let migree = PersistedARScene(savedAt: Date(), plants: [legacy],
                                      boundaryPoints: [[0, 0, 0]])
            .normalizedToWorldFrame()

        let plante = try XCTUnwrap(migree.plants.first)
        XCTAssertEqual(plante.position[0], 2.5, accuracy: 1e-6,
                       "sans migration effective, ce cas ne prouve rien")
        XCTAssertEqual(plante.position[2], -1.5, accuracy: 1e-6)
        XCTAssertEqual(plante.pot, attendu,
                       "le recentrage a reconstruit la plante sans son pot")
        XCTAssertEqual(plante.heightMeters, 0.64856,
                       "le recentrage a reconstruit la plante sans sa hauteur")
        // Ce que la migration était déjà censée préserver, pour qu'un ajout
        // de champ ne le fasse pas tomber en silence.
        XCTAssertEqual(plante.hasHeavy, true)
        XCTAssertEqual(plante.upAxis, "Y")
    }

    /// Une plante sans pot ne doit pas se voir en inventer un.
    func testEnregistrement_UnePlanteSansPotNenRecoitAucun() throws {
        let noeud = SCNNode()
        let capturee = PersistedPlant(
            noeud: noeud,
            plantID: "pothos", plantName: "Pothos",
            modelURLString: "Pothos.usdz",
            position: [0, 0, 0], rotation: [0, 0, 0], scale: [1, 1, 1],
            transform: transformMonde(x: 0, y: 0, z: 0),
            upAxis: nil, surfaceType: "floor", surfaceHeight: 0)
        XCTAssertNil(capturee.pot)
        XCTAssertNil(capturee.heightMeters, "0 = non mesurée, pas « 0 mètre »")
    }
}

// MARK: - Halo de sélection centré (#795)
//
// Ce que ces cas protègent : le halo est un clone AGRANDI du maillage. Agrandi
// autour de l'origine du nœud, il déplace chaque point proportionnellement à
// sa distance à cette origine. Une plante est proche de son origine, donc son
// halo paraissait juste ; le pot est attaché en contrebas, et son halo
// s'écartait d'autant.
//
// La position d'un halo se précalcule : c'est de la géométrie, pas du rendu.
// On demande donc à SceneKit où il place les coins du clone, pivot inclus —
// sans session AR ni appareil.

extension PlantPotCompositionTests {

    private static let echelleHalo: Float = 1.04

    /// Monte un halo au-dessus d'une boîte donnée et rend cette boîte telle
    /// que SceneKit la place dans le repère du parent, pivot compris.
    ///
    /// La mesure passe par `convertPosition`, et non par la boîte englobante
    /// du parent : `SCNNode.boundingBox` d'un nœud sans géométrie rend
    /// (0,0,0)-(0,0,0), et une mesure prise là ne prouverait rien. Sans
    /// rotation, les deux coins opposés suffisent à décrire la boîte.
    private func boiteDuHalo(sourceMin: SCNVector3, sourceMax: SCNVector3,
                             echelle: Float,
                             orientation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
    -> (min: SCNVector3, max: SCNVector3) {
        let parent = SCNNode()
        let halo = SCNNode()
        parent.addChildNode(halo)
        halo.simdOrientation = orientation
        halo.scale = SCNVector3(echelle, echelle, echelle)
        halo.pivot = HaloDeSelection.pivot(boiteMin: sourceMin, boiteMax: sourceMax,
                                           echelle: echelle,
                                           orientationDuClone: halo.simdOrientation)
        return (halo.convertPosition(sourceMin, to: parent),
                halo.convertPosition(sourceMax, to: parent))
    }

    /// Mêmes coins, sans halo : là où le conteneur voit la source.
    private func boiteDeLaSource(sourceMin: SCNVector3, sourceMax: SCNVector3,
                                 orientation: simd_quatf) -> (min: SCNVector3, max: SCNVector3) {
        let parent = SCNNode()
        let source = SCNNode()
        parent.addChildNode(source)
        source.simdOrientation = orientation
        return (source.convertPosition(sourceMin, to: parent),
                source.convertPosition(sourceMax, to: parent))
    }

    /// Garde-fou de convention. Le pivot s'applique À L'EXTÉRIEUR de la
    /// transformation du nœud : parent ← pivot⁻¹ · T·R·S. C'est la convention
    /// relevée sur appareil pour le pivot de pose (#113 : un pivot naïf
    /// `T(0, minY, 0)` laissait la plante 44 cm au-dessus du sol), et c'est
    /// celle que suit le calcul du halo. Si elle changeait, le défaut
    /// tomberait ici plutôt que de désaxer tous les halos en silence.
    func testHalo_ConventionDuPivotDansSceneKit() {
        let parent = SCNNode()
        let noeud = SCNNode()
        parent.addChildNode(noeud)
        noeud.scale = SCNVector3(2, 2, 2)
        noeud.pivot = SCNMatrix4MakeTranslation(0, 1, 0)
        XCTAssertEqual(noeud.convertPosition(SCNVector3(0, 1, 0), to: parent).y,
                       1, accuracy: 1e-5,
                       "pivot⁻¹ · S(2) : (0,1,0) doit atterrir à 2 − 1 = 1")
    }

    private func centre(_ boite: (min: SCNVector3, max: SCNVector3)) -> SCNVector3 {
        SCNVector3((boite.min.x + boite.max.x) / 2,
                   (boite.min.y + boite.max.y) / 2,
                   (boite.min.z + boite.max.z) / 2)
    }

    /// La plante seule : son halo est juste aujourd'hui, et doit le rester.
    func testHalo_UnNoeudCentreGardeSonHaloConcentrique() {
        let mn = SCNVector3(-0.2, -0.695, -0.2)
        let mx = SCNVector3(0.2, 0.695, 0.2)
        let halo = boiteDuHalo(sourceMin: mn, sourceMax: mx,
                               echelle: Self.echelleHalo)
        let c = centre(halo)
        XCTAssertEqual(c.x, 0, accuracy: 1e-5)
        XCTAssertEqual(c.y, 0, accuracy: 1e-5)
        XCTAssertEqual(c.z, 0, accuracy: 1e-5)
        XCTAssertEqual(halo.max.y - halo.min.y, 1.39 * Self.echelleHalo,
                       accuracy: 1e-4, "le halo doit bien rester agrandi")
    }

    /// Le pot : `attachPot` le pose sous la ligne de terre, donc loin de
    /// l'origine du porteur. C'est le cas qui tombait.
    func testHalo_UnNoeudDecaleGardeSonHaloConcentrique() {
        // Mesures d'un pot posé : lèvre à -0,105, bas à -0,350.
        let mn = SCNVector3(-0.145, -0.350, -0.145)
        let mx = SCNVector3(0.145, -0.105, 0.145)
        let attendu = centre((min: mn, max: mx))
        let halo = boiteDuHalo(sourceMin: mn, sourceMax: mx,
                               echelle: Self.echelleHalo)
        let c = centre(halo)
        XCTAssertEqual(c.y, attendu.y, accuracy: 1e-5,
                       "le halo du pot est désaxé : son centre a glissé")
        XCTAssertEqual(c.x, attendu.x, accuracy: 1e-5)
        XCTAssertEqual(c.z, attendu.z, accuracy: 1e-5)
        XCTAssertEqual(halo.max.y - halo.min.y, 0.245 * Self.echelleHalo,
                       accuracy: 1e-4, "le halo doit bien rester agrandi")
    }

    /// Un maillage décalé en x et en z aussi : le centre doit coïncider sur
    /// les trois axes, pas seulement sur la verticale.
    func testHalo_UnNoeudDecaleSurLesTroisAxes() {
        let mn = SCNVector3(0.30, -0.80, -0.50)
        let mx = SCNVector3(0.70, -0.40, -0.10)
        let attendu = centre((min: mn, max: mx))
        let c = centre(boiteDuHalo(sourceMin: mn, sourceMax: mx,
                                   echelle: Self.echelleHalo))
        XCTAssertEqual(c.x, attendu.x, accuracy: 1e-5)
        XCTAssertEqual(c.y, attendu.y, accuracy: 1e-5)
        XCTAssertEqual(c.z, attendu.z, accuracy: 1e-5)
    }

    /// Un porteur en Z-up est redressé de −90° autour de x. Le pivot
    /// s'appliquant du côté du conteneur, le centre doit y être exprimé :
    /// sinon le halo se recale de travers, et sur un axe inattendu.
    func testHalo_UnCloneRedresseEnZupResteConcentrique() {
        let rotationZup = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let mn = SCNVector3(-0.145, -0.350, -0.145)
        let mx = SCNVector3(0.145, -0.105, 0.145)
        let source = boiteDeLaSource(sourceMin: mn, sourceMax: mx,
                                     orientation: rotationZup)
        let attendu = centre(source)
        let c = centre(boiteDuHalo(sourceMin: mn, sourceMax: mx,
                                   echelle: Self.echelleHalo,
                                   orientation: rotationZup))
        XCTAssertEqual(c.x, attendu.x, accuracy: 1e-5)
        XCTAssertEqual(c.y, attendu.y, accuracy: 1e-5)
        XCTAssertEqual(c.z, attendu.z, accuracy: 1e-5)
    }

    /// Une échelle absurde ne doit pas produire un pivot absurde : mieux vaut
    /// le halo d'avant qu'un halo parti ailleurs.
    func testHalo_EchelleAberranteRendUnPivotNeutre() {
        let mn = SCNVector3(-0.1, -0.5, -0.1)
        let mx = SCNVector3(0.1, 0.5, 0.1)
        for echelle in [Float(0), -1, .nan, .infinity] {
            XCTAssertTrue(
                SCNMatrix4EqualToMatrix4(
                    HaloDeSelection.pivot(boiteMin: mn, boiteMax: mx, echelle: echelle),
                    SCNMatrix4Identity),
                "échelle \(echelle) acceptée à tort")
        }
    }
}
