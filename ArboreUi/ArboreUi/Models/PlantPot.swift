import Foundation

// PlantPot — composer une plante recoupée avec son pot. (#609, #623, #280)
//
// L'atelier 3D produit désormais des plantes **sans leur pot**, et mesure le
// socle sur lequel le pot vient se poser. Une telle plante ne peut pas
// s'afficher seule : il lui faut un pot, et l'échelle de ce pot dépend à la
// fois du socle de la plante et du rebord du pot.
//
// Le serveur résout le pot PAR DÉFAUT et le sert dans la charge de la plante,
// pour qu'un premier affichage n'ait pas à attendre un second aller-retour.
// Mais **changer** de pot ne repasse pas par lui : le socle est une mesure de
// la plante, indépendante du pot, et la bibliothèque se charge une fois. Tout
// est donc là pour recalculer en local — d'où l'aperçu instantané du sélecteur
// et la réouverture d'un jardin hors ligne.
//
// C'est la raison pour laquelle la règle vit ici, en un seul endroit, et pas
// en double avec le serveur : voir `ArboreBackend/pots.go`.

/// Socle mesuré par l'atelier, en **unités du modèle de la plante** et non en
/// centimètres : le maillage n'est pas à l'échelle réelle.
struct PlantPotBase: Codable, Equatable {
    /// Centre du socle.
    let x: Double
    /// Hauteur de la lèvre, où s'aligne le haut du pot.
    let y: Double
    let z: Double
    /// Rayon du socle. C'est lui qui donne l'échelle du pot.
    let radius: Double
    /// Ligne de terre, pour l'anti-clipping du feuillage retombant (#185/#623).
    /// Rarement mesurée à ce jour.
    let groundY: Double?
    /// Hauteur du végétal seul.
    let plantHeight: Double?

    enum CodingKeys: String, CodingKey {
        case x, y, z, radius, groundY, plantHeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        z = try c.decodeIfPresent(Double.self, forKey: .z) ?? 0
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0
        groundY = try c.decodeIfPresent(Double.self, forKey: .groundY)
        plantHeight = try c.decodeIfPresent(Double.self, forKey: .plantHeight)
    }

    init(x: Double, y: Double, z: Double, radius: Double,
         groundY: Double? = nil, plantHeight: Double? = nil) {
        self.x = x
        self.y = y
        self.z = z
        self.radius = radius
        self.groundY = groundY
        self.plantHeight = plantHeight
    }
}

/// Une entrée de la bibliothèque de pots. La bibliothèque est libre : un pot va
/// sous n'importe quelle plante.
struct Pot: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let modelURL: String
    /// Rayon du rebord, en unités du modèle **du pot**.
    let rimRadius: Double
    let height: Double
    let isDefault: Bool
    /// Empreinte du contenu de son USDZ, pour le cache (#294).
    let version: String?

    enum CodingKeys: String, CodingKey {
        case id, name, modelURL, rimRadius, height, version
        case isDefault = "default"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Pot"
        modelURL = try c.decodeIfPresent(String.self, forKey: .modelURL) ?? ""
        rimRadius = try c.decodeIfPresent(Double.self, forKey: .rimRadius) ?? 0
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 0
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        version = try c.decodeIfPresent(String.self, forKey: .version)
    }

    init(id: String, name: String, modelURL: String, rimRadius: Double,
         height: Double, isDefault: Bool = false, version: String? = nil) {
        self.id = id
        self.name = name
        self.modelURL = modelURL
        self.rimRadius = rimRadius
        self.height = height
        self.isDefault = isDefault
        self.version = version
    }
}

/// Empreintes du contenu des fichiers servis pour une fiche (#294).
///
/// Un champ par fichier : remplacer le modèle léger ne doit pas faire
/// retélécharger le lourd, qui pèse dix fois plus. Un champ absent signifie
/// « non calculé » et laisse le cache tel qu'il est.
struct PlantAssetVersions: Codable, Equatable {
    let model: String?
    let modelHeavy: String?
    let thumbnail: String?

    init(model: String? = nil, modelHeavy: String? = nil, thumbnail: String? = nil) {
        self.model = model
        self.modelHeavy = modelHeavy
        self.thumbnail = thumbnail
    }
}

/// Comment poser un pot sous une plante, dans le repère du modèle de la plante.
struct PotPlacement: Equatable {
    /// Facteur d'échelle uniforme à appliquer au modèle du pot.
    let scale: Double
    let x: Double
    let y: Double
    let z: Double
}

/// Disque de terre posé au fond du pot, pour combler l'anneau de paroi nue.
///
/// Pourquoi il faut un disque du tout : l'atelier ne conserve la terre qu'à
/// **75 % du rayon** (`_coeur`, « un quart de marge le garde dedans »), alors
/// que le pot est mis à l'échelle à 100 % de `socle.rayon`. La terre fait donc
/// les trois quarts de l'ouverture, et un anneau de paroi reste nu tout autour.
/// Mesuré sur le maillage du pot servi : l'ouverture vaut 0,0554 pour un rebord
/// à 0,0587, soit 94,5 % — l'anneau couvre bien un cinquième du rayon.
///
/// Le disque le masque sans toucher aux maillages, donc sans réexporter les
/// 2,3 Go du catalogue. Il reste juste le jour où `socle.rayon` sera corrigé
/// (#685) : il se dimensionne sur le pot, pas sur la plante.
///
/// Rayon et hauteurs sont dans le repère du modèle de la PLANTE, comme
/// `PotPlacement` — c'est le porteur qui subit la correction Z-up.
struct DisqueDeTerre: Equatable {
    let rayon: Double
    /// Hauteur de la face visible. Sous la lèvre : dans un vrai pot, la terre
    /// est en retrait du rebord, et l'aligner dessus donne un disque qui flotte.
    let y: Double
    let x: Double
    let z: Double
    let epaisseur: Double
}

enum PlantPotComposer {

    /// Pose du pot : mis à l'échelle `socle.rayon / rebord.rayon`, centré sur le
    /// socle, sa lèvre alignée sur `socle.y`.
    ///
    /// Rend `nil` quand la pose n'a pas de sens — socle absent, rayon ou rebord
    /// nul. Mieux vaut une plante visiblement nue qu'un pot posé au hasard :
    /// la première se répare, le second passe pour un bug d'AR. Le serveur
    /// applique déjà ce refus, celui-ci le tient aussi pour un pot choisi en
    /// local, qui ne repasse jamais par lui.
    static func placement(base: PlantPotBase?, pot: Pot?) -> PotPlacement? {
        guard let base, let pot,
              pot.rimRadius > 0, base.radius > 0,
              base.radius.isFinite, pot.rimRadius.isFinite else {
            return nil
        }
        return PotPlacement(scale: base.radius / pot.rimRadius, x: base.x, y: base.y, z: base.z)
    }

    /// Part du rebord occupée par l'OUVERTURE du pot.
    ///
    /// `rimRadius` est le rayon EXTÉRIEUR : mesuré sur le maillage servi, la
    /// paroi forme deux coques, l'extérieure à 0,0589 et l'intérieure à 0,0554.
    /// Poser le disque au rayon du rebord le ferait traverser la paroi.
    ///
    /// Une constante tant que la bibliothèque ne compte qu'un pot. Le jour où
    /// un second arrive, c'est une mesure à porter sur sa fiche, pas un
    /// réglage à ajuster : 0,9445 décrit CE pot, pas une règle générale.
    static let partOuverture = 0.9445

    /// Retrait de la face de terre sous la lèvre, en part de la hauteur du pot.
    static let retraitTerre = 0.06

    /// Disque de terre à poser dans le pot, ou `nil` s'il n'a pas de sens.
    ///
    /// Prend les dimensions du pot **déjà mis à l'échelle**, telles que chaque
    /// moteur les lit sur le maillage chargé, et non les champs de la fiche :
    /// l'AR ne dispose que d'un `PersistedPot`, qui porte la pose mais ni
    /// `rimRadius` ni `height`. Mesurer les bornes est de toute façon plus sûr
    /// que de croire la fiche — c'est le maillage qu'on affiche.
    ///
    /// Rend `nil` aux mêmes conditions que `placement` : sans dimensions
    /// utilisables, pas de disque. Mieux vaut un anneau nu qu'un disque au
    /// hasard, qui passerait pour un défaut d'affichage.
    static func disque(pose: PotPlacement?,
                       rayonExterieurPose: Double,
                       hauteurPose: Double) -> DisqueDeTerre? {
        guard let pose,
              rayonExterieurPose > 0, rayonExterieurPose.isFinite,
              hauteurPose > 0, hauteurPose.isFinite else { return nil }
        // 0,985 : une marge contre le z-fighting avec la paroi intérieure.
        let rayon = rayonExterieurPose * partOuverture * 0.985
        guard rayon > 0 else { return nil }
        return DisqueDeTerre(rayon: rayon,
                             y: pose.y - hauteurPose * retraitTerre,
                             x: pose.x, z: pose.z,
                             epaisseur: hauteurPose * 0.02)
    }

    /// Pot à afficher parmi ceux de la bibliothèque.
    ///
    /// Le repli sur le pot par défaut est volontaire : le choix de l'utilisateur
    /// est persisté dans son jardin, et si ce pot quitte la bibliothèque, la
    /// scène doit continuer à s'afficher plutôt que de perdre sa plante.
    static func pot(parmi pots: [Pot], choisi: String?) -> Pot? {
        guard !pots.isEmpty else { return nil }
        if let choisi, let trouve = pots.first(where: { $0.id == choisi }) {
            return trouve
        }
        return pots.first(where: { $0.isDefault }) ?? pots.first
    }
}

extension Plant {

    /// Pot à poser sous cette plante, et sa pose. `nil` si elle n'en attend pas.
    ///
    /// C'est le **seul** endroit qui répond à « cette plante a-t-elle besoin
    /// d'un pot, lequel, et où ». Catalogue, vignette et AR passent par ici :
    /// l'invariant ne peut donc pas être oublié par un appelant, et il n'y a
    /// qu'un endroit à corriger le jour où la règle change.
    ///
    /// - Parameters:
    ///   - choisi: identifiant du pot retenu par l'utilisateur, persisté dans
    ///     son jardin. `nil` = celui que le serveur a servi, sinon le défaut.
    ///   - bibliotheque: pots connus du client, pour un choix fait en local.
    ///     Vide, on s'en tient au pot servi avec la fiche.
    func potEtPose(choisi: String? = nil,
                   bibliotheque: [Pot] = []) -> (pot: Pot, pose: PotPlacement)? {
        guard attendUnPot else { return nil }

        // Le pot servi avec la fiche fait partie des candidats : sans lui, un
        // client qui n'a pas encore chargé la bibliothèque n'aurait rien à
        // poser, et la plante s'afficherait nue le temps d'un aller-retour.
        var candidats = bibliotheque
        if let servi = pot, !candidats.contains(where: { $0.id == servi.id }) {
            candidats.append(servi)
        }

        guard let retenu = PlantPotComposer.pot(parmi: candidats, choisi: choisi),
              let pose = PlantPotComposer.placement(base: potBase, pot: retenu) else {
            return nil
        }
        return (retenu, pose)
    }
}

extension PersistedPot {

    /// Enregistre un pot et sa pose pour qu'un jardin se rouvre sans réseau.
    init(pot: Pot, pose: PotPlacement) {
        self.init(potID: pot.id,
                  modelURLString: pot.modelURL,
                  scale: Float(pose.scale),
                  offset: [Float(pose.x), Float(pose.y), Float(pose.z)],
                  version: pot.version)
    }

    /// Pose relue d'un jardin enregistré. `nil` si l'enregistrement est amputé :
    /// mieux vaut une plante nue qu'un pot posé au hasard.
    var pose: PotPlacement? {
        guard offset.count == 3, scale > 0, scale.isFinite else { return nil }
        return PotPlacement(scale: Double(scale),
                            x: Double(offset[0]), y: Double(offset[1]), z: Double(offset[2]))
    }
}
