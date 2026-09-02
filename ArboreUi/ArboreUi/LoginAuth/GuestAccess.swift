import FirebaseAuth
import SwiftUI

// GuestAccess.swift — accès invité (issue #391).
//
// Le backend distingue le rôle `guest` (session Firebase anonyme) du rôle
// `member`, et ferme aux invités tout ce qui suppose un compte durable :
// jardins, profil, consentements, export RGPD. Ces routes répondent
// `403 ACCOUNT_REQUIRED`, que `NetworkManager` remonte en
// `NetworkError.accountRequired`.
//
// Ce fichier regroupe les trois éléments côté client :
//   1. `GuestSession`  — savoir si la session courante est anonyme
//   2. `AccountRequiredPresenter` — l'invitation à créer un compte
//   3. `ContinueAsGuestButton`    — le point d'entrée sur login et inscription

// MARK: - 1. État de la session

enum GuestSession {
    /// Vrai si la session Firebase courante est anonyme.
    ///
    /// L'information est **locale** : le SDK Firebase la porte dans l'objet
    /// utilisateur, aucune route de vérification de rôle n'est nécessaire.
    /// C'est aussi la seule source à utiliser côté client — le backend, lui,
    /// la déduit de `sign_in_provider` dans le token signé, que le client ne
    /// peut pas falsifier.
    static var isGuest: Bool {
        Auth.auth().currentUser?.isAnonymous == true
    }

    /// Ouvre une session invité.
    ///
    /// Ne pose **aucun** document utilisateur en base et n'enregistre aucun
    /// consentement : un invité n'a pas de profil serveur, et `POST /users`
    /// comme `POST /consents` lui répondraient `403 ACCOUNT_REQUIRED`. Appeler
    /// `saveUserToBackend` ou `recordInitialConsents` ici par symétrie avec le
    /// signup produirait deux 403 à chaque démarrage invité.
    static func signIn(completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().signInAnonymously { _, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    /// Quitte la session invité pour rejoindre l'écran d'authentification.
    ///
    /// La session anonyme est **fermée**. Tant que `linkWithCredential` n'est
    /// pas en place (#391, section 4), l'uid anonyme ne peut pas être conservé
    /// à travers une inscription ; le laisser ouvert derrière un écran de
    /// connexion produirait un état incohérent — utilisateur Firebase présent,
    /// application affichant « déconnecté ».
    ///
    /// Les jardins déjà créés restent sur l'appareil : ce sont des fichiers
    /// locaux (`scene_*.json`, WorldMap), indépendants de la session.
    static func exitToAuthentication() {
        // Même raison qu'à la déconnexion ordinaire (#394) : les bascules
        // `privacy_*` sont locales et survivraient à la session, faisant
        // hériter au compte suivant des choix d'un invité.
        LocalDataOwnership.clearConsentStateOnLogout()
        try? Auth.auth().signOut()
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
    }
}

// MARK: - 2. Invitation à créer un compte

/// Modificateur présentant l'invitation quand une action est refusée à un
/// invité. Centralisé pour que le message et les actions restent identiques
/// partout — l'alternative serait une alerte réécrite dans chaque écran.
struct AccountRequiredAlert: ViewModifier {
    @Binding var isPresented: Bool
    var onCreateAccount: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            L10n.t("GUEST_ACCOUNT_REQUIRED_TITLE"),
            isPresented: $isPresented
        ) {
            Button(L10n.t("GUEST_ACCOUNT_REQUIRED_CTA")) { onCreateAccount() }
            Button(L10n.t("COMMON_CANCEL"), role: .cancel) {}
        } message: {
            Text(L10n.t("GUEST_ACCOUNT_REQUIRED_MESSAGE"))
        }
    }
}

extension View {
    /// Présente l'invitation à créer un compte.
    ///
    /// À brancher sur un `@State` que l'appelant passe à `true` lorsqu'il
    /// intercepte `NetworkError.accountRequired`.
    func accountRequiredAlert(
        isPresented: Binding<Bool>,
        onCreateAccount: @escaping () -> Void
    ) -> some View {
        modifier(AccountRequiredAlert(isPresented: isPresented, onCreateAccount: onCreateAccount))
    }
}

extension Error {
    /// Vrai si l'erreur est un refus faute de compte.
    ///
    /// Évite d'écrire `if case NetworkError.accountRequired = error` sur chaque
    /// site d'appel, et rend le test lisible dans un `catch` générique.
    var isAccountRequired: Bool {
        // Le cast est nécessaire : dans une extension de `Error`, `self` est du
        // type concret conforme, pas de l'existentiel — un `if case` direct ne
        // compile pas.
        guard let networkError = self as? NetworkError else { return false }
        if case .accountRequired = networkError { return true }
        return false
    }
}

// MARK: - 3. Point d'entrée

/// Bouton « continuer sans compte », posé sur l'écran de connexion et en bas
/// de l'inscription.
///
/// Traitement **fantôme** — texte seul, sans fond ni contour — délibérément.
/// La hiérarchie de `LoginView` compte déjà un bouton primaire rempli vert, le
/// bouton Apple natif et le bouton Google (fond `card` + contour) : un
/// quatrième bouton plein ferait de l'accès invité une option de même poids
/// que la connexion, et un remplissage vert le mettrait en concurrence directe
/// avec le CTA principal.
struct ContinueAsGuestButton: View {
    var onSignedIn: () -> Void

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 6) {
            Button(action: start) {
                HStack(spacing: 8) {
                    if isSigningIn {
                        ProgressView().scaleEffect(0.8)
                    }
                    Text(L10n.t("AUTH_CONTINUE_AS_GUEST"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .disabled(isSigningIn)
            .buttonStyle(.plain)

            // Le sous-titre annonce ce que l'invité PERD, pas ce qu'il gagne.
            // Sans cela, la déception arrive au premier jardin non sauvegardé,
            // c'est-à-dire après plusieurs minutes de travail.
            Text(L10n.t("AUTH_CONTINUE_AS_GUEST_SUBTITLE"))
                .font(.system(size: 12))
                .foregroundColor(ArboreDesign.Colors.placeholder)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(ArboreDesign.Colors.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 30)
    }

    private func start() {
        errorMessage = nil
        isSigningIn = true
        GuestSession.signIn { result in
            isSigningIn = false
            switch result {
            case .success:
                onSignedIn()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Message lisible pour une réponse d'erreur du backend (#391).
///
/// Ces deux écrans affichaient le corps brut de la réponse : un invité y aurait
/// lu `{"code":"ACCOUNT_REQUIRED","error":"..."}`. On traduit le seul code
/// attendu ici et on masque le reste, qui n'apprend rien à l'utilisateur et
/// peut exposer des détails internes.
enum BackendErrorMessage {
    static func humanReadable(from data: Data, fallback: String) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (obj["code"] as? String) == "ACCOUNT_REQUIRED" {
            return L10n.t("GUEST_ACCOUNT_REQUIRED_MESSAGE")
        }
        return fallback
    }
}
