import Foundation

/// Les bornes chiffrées qui décident de ce qu'on montre et de ce qu'on
/// recommande, définies **une seule fois**.
///
/// #792 a retiré les décisions prises sur de la prose. Ce fichier ferme la
/// famille voisine : celles prises sur un nombre recopié d'un fichier à
/// l'autre (#793).
///
/// L'arrosage en portait la preuve. Le filtre disait « peu d'arrosage = 10
/// jours et plus », l'évaluateur de compatibilité se satisfaisait de 7 : une
/// plante à 7–8 jours était donc un **bon choix** pour l'évaluateur et
/// **invisible** pour le filtre. L'utilisateur qui déclarait arroser peu
/// recevait une recommandation qui ne survivait pas à son propre filtre.
///
/// La lumière n'avait pas encore divergé, mais ses bornes étaient recopiées à
/// quatre endroits, dont un ajouté avec un commentaire qui *demandait* la
/// cohérence sans la produire. Un commentaire ne tient pas un invariant.
enum PlantThresholds {

    /// Heures de lumière directe par jour.
    enum Light {
        /// Au-delà, on ne parle plus d'ombre.
        ///
        /// Trois heures est le seuil de `appendSunlightCriterion` depuis
        /// l'origine du moteur ; il est conservé tel quel, le but de #793
        /// étant de le partager et non de le rejuger.
        static let shadeMaxHours: Double = 3

        /// En deçà, on ne parle pas de plein soleil.
        static let fullSunMinHours: Double = 6
    }

    /// Intervalle entre deux arrosages, en jours.
    ///
    /// Trois seaux pour trois boutons, et ils **partitionnent** la droite :
    /// tout intervalle tombe dans exactement un seau, sans trou ni
    /// recouvrement. C'est ce qui permet au filtre et à l'évaluateur de dire
    /// la même chose d'une même plante.
    enum Watering {
        /// « Souvent » : jusqu'à trois jours.
        static let frequentMaxDays: Double = 3

        /// « Modéré » : de quatre à neuf jours.
        static let moderateMinDays: Double = 4
        static let moderateMaxDays: Double = 9

        /// « Peu » : dix jours et plus.
        ///
        /// C'est la borne qui a tranché la contradiction de #793. L'évaluateur
        /// acceptait 7 ; il lit désormais cette valeur. Le changement est
        /// volontairement **restrictif** : il retire des plantes de la
        /// catégorie « bon choix » pour un utilisateur peu disponible plutôt
        /// que d'en montrer qu'il ne pourra pas garder.
        static let sparseMinDays: Double = 10
    }

    /// Les poids du moteur de suggestion.
    ///
    /// Aucun n'était faux ; aucun ne disait pourquoi il valait ça. Un réglage
    /// futur du barème se faisait donc à l'aveugle, et un test vérifiant un
    /// score attendu — il en existe depuis #792 — tombait sans qu'on sache si
    /// le barème avait changé ou si la plante avait changé.
    enum Scoring {
        /// Ce que coûte un verdict qui n'est pas franchement « adaptée ».
        ///
        /// Une plante seulement « probablement compatible » reste proposable,
        /// mais elle ne doit pas devancer une plante certifiée : 0,78 est
        /// l'écart qui la laisse passer derrière.
        static let unconfirmedConfidence: Double = 0.78

        /// Ce que coûte **chaque** donnée manquante, et le plafond du total.
        ///
        /// Le plafond existe pour qu'une fiche très incomplète reste
        /// comparable plutôt que d'être écrasée à zéro : notre trou de données
        /// n'est pas un défaut de la plante.
        static let missingDataPenalty: Double = 0.025
        static let missingDataPenaltyCap: Double = 0.20

        /// En dessous, une plante n'est pas proposée du tout.
        static let minimumSuggestionScore: Double = 0.25

        /// Au-dessus, un jardin est annoncé comme bien assorti.
        static let wellMatchedGardenScore: Double = 0.75

        /// Combien de plantes d'une même nature au maximum dans une
        /// suggestion. La règle de diversité : trois hortensias ne sont pas
        /// une composition.
        static let maxPlantsPerKind = 2

        /// Le score plancher d'un niveau « à confirmer » pour rester affiché
        /// dans le catalogue (`PlantCatalogContext`).
        static let reviewableFloor: Double = 0.55
    }
}
