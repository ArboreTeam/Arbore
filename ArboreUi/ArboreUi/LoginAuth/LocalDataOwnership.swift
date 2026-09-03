import FirebaseAuth
import Foundation

// LocalDataOwnership.swift — cloisonnement des données locales par compte (#394).
//
// Les fichiers écrits sur l'appareil ne portaient aucune identité : `scene_<id>`,
// `worldmap_<id>`, `wizard_<id>` sont nommés d'après le jardin, jamais d'après
// son propriétaire. Toute session — un autre compte, ou un invité — voyait donc
// les jardins de la précédente.
//
// Principe retenu : **enregistrer le propriétaire, filtrer à la lecture, ne
// jamais supprimer**.
//
// La suppression au logout est la solution qui vient spontanément, et c'est la
// pire : les données AR (`scene_*.json` + `worldmap_*.arexperience`) n'existent
// QUE sur l'appareil — le serveur ne stocke que les métadonnées du jardin, pas
// la scène. Purger au logout détruirait le seul exemplaire, et l'utilisateur qui
// se reconnecte ne retrouverait que des écrans « Jardin indisponible ».
//
// Avec ce mécanisme, A se déconnecte, B ne voit rien de A, et A retrouve tout en
// revenant.

enum LocalDataOwnership {

    // MARK: - Stockage

    /// Table `identifiant → uid propriétaire`, en JSON dans Documents.
    ///
    /// Un fichier annexe plutôt qu'un champ dans `PersistedARScene` : le format
    /// de scène porte déjà une migration de repère (#170) et son décodage est
    /// sensible. Un renommage des fichiers aurait par ailleurs cassé les
    /// installations existantes.
    private static let fileName = "local_data_owners.json"

    private static var storeURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL),
              let table = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return table
    }

    private static func save(_ table: [String: String]) {
        guard let data = try? JSONEncoder().encode(table) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - Session courante

    /// `uid` de la session courante, ou `nil` si personne n'est connecté.
    static var currentUID: String? {
        Auth.auth().currentUser?.uid
    }

    /// Vrai si la session courante est anonyme.
    ///
    /// Utilisé pour ne **jamais** attribuer un contenu hérité à un invité :
    /// l'uid anonyme est purgé par Firebase au bout de 30 jours, ce qui rendrait
    /// le jardin définitivement invisible à son véritable auteur.
    static var currentSessionIsAnonymous: Bool {
        Auth.auth().currentUser?.isAnonymous == true
    }

    // MARK: - Lecture et écriture

    /// Propriétaire enregistré d'un identifiant, ou `nil` s'il est inconnu.
    static func owner(of identifier: String) -> String? {
        load()[identifier]
    }

    /// Attribue un identifiant à la session courante.
    ///
    /// **Les invités sont admis ici, contrairement à la migration.** La
    /// distinction est essentielle et vaut d'être explicitée :
    ///
    ///   - `claim` est appelée à la **création** du contenu. L'invité en est
    ///     l'auteur, il n'y a personne à qui le cacher. Le lui refuser le
    ///     rendrait invisible à ses propres yeux dès le rafraîchissement
    ///     suivant, puisque `isVisibleInCurrentSession` masque tout contenu
    ///     sans propriétaire en session anonyme.
    ///   - La migration, elle, attribue un contenu **préexistant** dont
    ///     l'auteur est inconnu. Un invité ne doit jamais se l'approprier :
    ///     l'uid anonyme est purgé par Firebase au bout de 30 jours, ce qui
    ///     rendrait le jardin définitivement invisible à son véritable auteur.
    ///     C'est `isVisibleInCurrentSession` qui l'interdit, en sortant avant
    ///     d'appeler `claim`.
    ///
    /// Conséquence assumée : le jardin d'un invité disparaît avec son compte
    /// anonyme. C'est cohérent avec le fait qu'un invité qui crée un compte
    /// repart de zéro tant que `linkWithCredential` n'existe pas (#391).
    static func claim(_ identifier: String) {
        guard let uid = currentUID else { return }
        var table = load()
        guard table[identifier] != uid else { return }
        table[identifier] = uid
        save(table)
    }

    /// Oublie un identifiant. À appeler quand la donnée elle-même est supprimée,
    /// pour que la table ne grossisse pas indéfiniment.
    static func forget(_ identifier: String) {
        var table = load()
        guard table.removeValue(forKey: identifier) != nil else { return }
        save(table)
    }

    // MARK: - Visibilité

    /// Décide si un contenu local est visible par la session courante.
    ///
    /// Trois cas :
    ///
    ///   - **propriétaire connu** → visible uniquement par lui ;
    ///   - **propriétaire inconnu, session nominative** → visible, et attribué
    ///     au passage. C'est la migration des fichiers antérieurs à #394 : la
    ///     très grande majorité des appareils n'a servi qu'à un seul compte, et
    ///     cacher son propre contenu à l'utilisateur serait pire que le risque
    ///     couvert ;
    ///   - **propriétaire inconnu, session anonyme** → masqué. Un invité ne doit
    ///     jamais hériter d'un contenu qu'il n'a pas produit, et c'est
    ///     exactement le cas rapporté dans #394.
    ///
    /// Personne connecté → rien n'est visible.
    static func isVisibleInCurrentSession(_ identifier: String) -> Bool {
        guard let uid = currentUID else { return false }

        if let owner = owner(of: identifier) {
            return owner == uid
        }

        if currentSessionIsAnonymous {
            return false
        }

        claim(identifier)
        return true
    }

    // MARK: - Consentements

    /// Clés `UserDefaults` effacées à la déconnexion.
    ///
    /// Ce sont les **seules** données locales liées au compte que l'on peut
    /// effacer sans perte : le serveur détient la preuve de consentement
    /// (`GET /consents/latest`), et `PrivacySettingsView` la relit à la
    /// connexion suivante.
    ///
    /// Les effacer n'est pas une commodité mais une nécessité : `privacy_shareData`
    /// gouverne l'activation de Sentry (opt-in strict, #226). Les laisser en
    /// place ferait hériter au compte suivant — ou à une session invité — un
    /// consentement qu'il n'a jamais donné. Un consentement est personnel et non
    /// transférable.
    private static let consentKeyPrefixes = ["privacy_", "consent_"]
    private static let consentKeys = ["consent_history"]

    /// Efface les consentements du compte qui se déconnecte.
    ///
    /// Ne touche à **rien d'autre** : ni les scènes AR, ni le chat, ni les
    /// routines d'arrosage — aucun de ces contenus n'existe ailleurs que sur
    /// l'appareil. Ils sont masqués par `isVisibleInCurrentSession`, pas
    /// supprimés.
    static func clearConsentStateOnLogout() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            if consentKeyPrefixes.contains(where: key.hasPrefix) || consentKeys.contains(key) {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
