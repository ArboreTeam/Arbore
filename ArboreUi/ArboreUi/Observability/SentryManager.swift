//
//  SentryManager.swift
//  ArboreUi
//
//  Thin wrapper around the Sentry SDK (issue #205).
//
//  Tout est gardé derrière `isEnabled` : si aucun DSN n'est configuré dans
//  Secrets.xcconfig (cf. AppConfig.sentryDSN), Sentry ne démarre pas et toutes
//  les méthodes sont des no-op. L'app se comporte donc à l'identique sans
//  secrets — pratique pour les contributeurs et la CI.
//

import Foundation
import Sentry

enum SentryManager {

    /// Clé `AppStorage` du consentement diagnostic/analytics (toggle « Partage
    /// de données » dans PrivacySettingsView). Absente = `false` : opt-out par
    /// défaut, Sentry ne démarre pas tant que l'utilisateur n'a pas accepté.
    private static let consentKey = "privacy_shareData"

    /// Vrai si un DSN est configuré dans Secrets.xcconfig.
    static var isConfigured: Bool { !AppConfig.sentryDSN.isEmpty }

    /// Vrai si l'utilisateur a consenti au partage des données de diagnostic.
    static var hasConsent: Bool { UserDefaults.standard.bool(forKey: consentKey) }

    /// Vrai si le crash reporting tourne — DSN présent suffit désormais (#469).
    ///
    /// L'opt-in ne conditionne plus la COLLECTE, mais l'IDENTIFICATION. Voir
    /// `start()` pour ce que cela change concrètement.
    static var isEnabled: Bool { isConfigured }

    /// Démarre Sentry dès qu'un DSN est configuré. Appelée au tout début de
    /// `AppDelegate.didFinishLaunchingWithOptions`, AVANT `FirebaseApp.configure()`,
    /// pour capturer un éventuel crash d'initialisation.
    ///
    /// ## Deux régimes, et ce qui les sépare
    ///
    /// **Sans consentement — anonyme.** Aucun identifiant ne quitte l'appareil :
    /// ni UID Firebase, ni identifiant d'installation, ni adresse IP. Pas de
    /// hiérarchie de vues (elle contient les textes affichés), pas de fil
    /// d'Ariane réseau (les URL portent des identifiants de jardin), pas de
    /// traces de performance. Il reste la pile d'appel, la version de l'app et
    /// le modèle d'appareil — de quoi corriger un plantage, pas de quoi
    /// reconnaître quelqu'un.
    ///
    /// **Avec consentement — rattaché.** L'UID Firebase est joint, ce qui permet
    /// de relier plusieurs plantages au même compte et de répondre à un
    /// signalement précis. La hiérarchie de vues et les traces reviennent.
    ///
    /// ## Pourquoi la collecte anonyme n'attend pas le consentement
    ///
    /// Le RGPD porte sur les données à caractère personnel (art. 4). Une donnée
    /// véritablement anonyme — qui ne permet plus d'identifier une personne, ni
    /// directement ni par recoupement — sort de son champ (considérant 26).
    ///
    /// Le régime anonyme ci-dessous vise ce seuil, et c'est pourquoi il retire
    /// l'UID : un pseudonyme reste une donnée personnelle, si stable qu'il
    /// permet de suivre un individu dans le temps.
    ///
    /// ⚠️ **Deux conditions ne dépendent pas de ce code et doivent être tenues :**
    /// la politique de confidentialité doit décrire cette collecte, et le
    /// réglage Sentry « Prevent Storing of IP Addresses » doit être activé côté
    /// projet — le SDK n'envoie pas l'IP, mais l'ingest la voit passer.
    static func start() {
        guard isConfigured else {
            #if DEBUG
            print("ℹ️ Sentry désactivé (aucun DSN dans Secrets.xcconfig).")
            #endif
            return
        }

        SentrySDK.start { options in
            options.dsn = AppConfig.sentryDSN
            options.environment = AppConfig.environment
            options.releaseName = AppConfig.sentryReleaseName
            options.dist = AppConfig.buildNumber

            let consenti = hasConsent

            // Traces de performance : seulement avec consentement. Leurs noms de
            // transaction portent des chemins tels que `/gardens/<id>` — un
            // identifiant de ressource, donc un fil à tirer. Sans consentement,
            // seuls les plantages remontent.
            options.tracesSampleRate = consenti ? 0.1 : 0.0

            // Jamais de capture d'écran : elle peut montrer n'importe quoi.
            options.attachScreenshot = false

            // La hiérarchie de vues contient les TEXTES affichés — noms de
            // jardin, de plantes, saisies en cours. Utile pour diagnostiquer un
            // crash d'UI, incompatible avec l'anonymat.
            options.attachViewHierarchy = consenti

            // Minimisation RGPD : ne jamais joindre les PII collectées « par
            // défaut » par le SDK (adresse IP, etc.).
            options.sendDefaultPii = false
            // Défense en profondeur, appliquée à CHAQUE événement.
            // La logique vit dans `scrub` et `filtrer`, hors de ces closures,
            // pour être vérifiable sans démarrer le SDK (#496, #498).
            options.beforeSend = { Self.scrub($0, consenti: consenti) }
            options.beforeBreadcrumb = { Self.filtrer($0, consenti: consenti) }


            #if DEBUG
            options.debug = true
            #endif
        }
    }

    // MARK: - Anonymisation

    /// Retire d'un événement ce qui pourrait désigner une personne.
    ///
    /// Extraite de `start()` pour être vérifiable. La relecture n'avait pas
    /// suffi : elle avait laissé passer `device_app_hash`, découvert sur le
    /// premier événement réel (#498). Une closure imbriquée n'est atteignable
    /// par aucun test.
    ///
    /// Dans les DEUX régimes : IP, e-mail, nom, corps de requête.
    ///
    /// Sans consentement, deux retraits de plus :
    ///
    /// - `user` en entier, ce qui emporte l'UID Firebase et l'identifiant que le
    ///   SDK génère de lui-même ;
    /// - `device_app_hash` dans le contexte `app` — un identifiant
    ///   d'INSTALLATION, stable d'un lancement à l'autre. Il ne vit PAS dans
    ///   `user`, ce qui l'avait fait échapper au premier correctif.
    ///
    /// `app_id` est délibérément CONSERVÉ : vérifié contre le dSYM téléversé,
    /// c'est l'UUID du binaire, identique pour tous les porteurs d'un même
    /// build. Le retirer casserait la symbolication sans rien gagner.
    static func scrub(_ event: Event, consenti: Bool) -> Event {
        event.user?.ipAddress = nil
        event.user?.email = nil
        event.user?.username = nil
        event.user?.name = nil
        event.user?.data = nil
        event.serverName = nil
        event.request = nil

        guard !consenti else { return event }

        event.user = nil
        if var contexts = event.context, var app = contexts["app"] {
            app.removeValue(forKey: "device_app_hash")
            contexts["app"] = app
            event.context = contexts
        }
        return event
    }

    /// Écarte les fils d'Ariane qui rattacheraient l'événement à des ressources.
    ///
    /// Les URL de l'app portent `/gardens/<id>` et `/plants/<id>` : par
    /// recoupement, elles désignent leur propriétaire.
    static func filtrer(_ crumb: Breadcrumb, consenti: Bool) -> Breadcrumb? {
        if !consenti && (crumb.type == "http" || crumb.category == "http") {
            return nil
        }
        return crumb
    }

    /// Réagit à un changement du consentement depuis PrivacySettingsView.
    ///
    /// Le retrait ne coupe PLUS la collecte : il la ramène au régime anonyme
    /// (#469). Sentry est donc redémarré pour que les options — hiérarchie de
    /// vues, traces, fil d'Ariane réseau — soient réévaluées, et le contexte
    /// utilisateur est effacé.
    ///
    /// Redémarrer plutôt que reconfigurer : `SentrySDK` fige ses options au
    /// démarrage, et les modifier après coup laisserait la hiérarchie de vues
    /// active alors que l'utilisateur vient de la refuser.
    static func updateConsent(granted: Bool, uid: String?) {
        guard isConfigured else { return }
        SentrySDK.close()
        start()
        if granted, let uid {
            setUser(uid: uid)
        }
    }

    /// Rattache les events au user via son UID Firebase (pseudonyme).
    ///
    /// **Sans consentement, c'est un no-op** : le pseudonyme est précisément ce
    /// qui distingue une donnée anonyme d'une donnée personnelle.
    static func setUser(uid: String) {
        guard isEnabled, hasConsent else { return }
        let user = Sentry.User()        // Sentry.User, à ne pas confondre avec le modèle `User` de l'app
        user.userId = uid
        SentrySDK.setUser(user)
    }

    /// Efface le contexte user (au logout).
    static func clearUser() {
        guard isEnabled else { return }
        SentrySDK.setUser(nil)
    }

    #if DEBUG
    /// Envoie un event de test non-crashant pour vérifier que le DSN
    /// fonctionne (visible sur sentry.io en quelques secondes).
    static func sendTestEvent() {
        guard isEnabled else {
            print("⚠️ Sentry désactivé : renseigne le DSN dans Secrets.xcconfig.")
            return
        }
        SentrySDK.capture(message: "Arbore test event — \(AppConfig.sentryReleaseName)")
    }
    #endif
}
