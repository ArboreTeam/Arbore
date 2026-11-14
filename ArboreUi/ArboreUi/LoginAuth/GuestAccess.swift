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
    @State private var showAcceptance = false

    /// Acceptation des documents par un invité, avec les versions acceptées
    /// (#841).
    ///
    /// Un invité ne pouvait accepter nulle part : le texte d'acceptation vit
    /// sur l'écran d'inscription, qu'il contourne par définition. Ses CGU
    /// relevaient donc du seul « en utilisant cette app, vous acceptez » —
    /// la forme la plus faible qui existe, et sans même un point de passage.
    /// Or c'est dans les CGU que vit désormais l'avertissement sur la
    /// toxicité : une clause ne vaut que ce que vaut son acceptation.
    ///
    /// Le stockage est LOCAL, et c'est le seul possible : `POST /consents`
    /// répond `403 ACCOUNT_REQUIRED` à une session anonyme. La preuve n'a donc
    /// pas la valeur d'une entrée du registre serveur — elle a celle d'un acte
    /// positif, horodaté par les versions qu'il désigne.
    ///
    /// Comparer les versions, et non un booléen, fait de ce réglage le
    /// mécanisme qui honore la clause `TERMS_SECTION_AVAILABILITY_ITEM3` :
    /// quand un document monte de version, l'invité est resollicité.
    @AppStorage("guestAcceptedDocuments") private var acceptedDocuments = ""

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
        .sheet(isPresented: $showAcceptance) {
            GuestAcceptanceSheet {
                acceptedDocuments = currentDocuments
                signIn()
            }
        }
    }

    /// Les versions actuellement en vigueur, telles qu'elles seront stockées.
    private var currentDocuments: String {
        "terms:\(AppConfig.termsVersion)|privacy:\(AppConfig.privacyPolicyVersion)"
    }

    private var hasAcceptedCurrentDocuments: Bool {
        acceptedDocuments == currentDocuments
    }

    /// Ouvre la session, ou demande d'abord l'acceptation.
    private func start() {
        errorMessage = nil
        guard hasAcceptedCurrentDocuments else {
            showAcceptance = true
            return
        }
        signIn()
    }

    private func signIn() {
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

// MARK: - 4. Acceptation des documents par un invité

/// Demandée avant d'ouvrir une session anonyme (#841).
///
/// Posée sur `ContinueAsGuestButton` et non sur chaque écran : le bouton vit à
/// la fois sur `LoginView` et sur `SignUpView`, et une porte verrouillée d'un
/// seul côté ne verrouille rien.
///
/// Le corps nomme la toxicité explicitement. Un écran d'acceptation qui ne
/// dirait pas de QUOI il s'agit ne serait qu'une formalité de plus à balayer,
/// et c'est précisément ce que l'acceptation par l'usage avait de faible.
private struct GuestAcceptanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasAccepted = false
    var onAccepted: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.t("GUEST_ACCEPT_TITLE"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Text(L10n.t("GUEST_ACCEPT_BODY"))
                    .font(.system(size: 15))
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Button(action: { hasAccepted.toggle() }) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: hasAccepted ? "checkmark.square.fill" : "square")
                                .foregroundColor(hasAccepted ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.textSecondary)
                            Text(L10n.t("AUTH_AGREE_CHECKBOX"))
                                .foregroundColor(ArboreDesign.Colors.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .accessibilityLabel(L10n.t("AUTH_AGREE_CHECKBOX"))
                    .accessibilityAddTraits(hasAccepted ? [.isButton, .isSelected] : .isButton)

                    VStack(spacing: 2) {
                        NavigationLink(destination: TermsConditionsView()) {
                            Text(NSLocalizedString("AUTH_AGREE_TERMS", comment: ""))
                                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                                .underline()
                        }

                        HStack(spacing: 4) {
                            Text(NSLocalizedString("AUTH_AGREE_AND", comment: ""))
                                .foregroundColor(ArboreDesign.Colors.textSecondary)

                            NavigationLink(destination: PrivacyPolicyView()) {
                                Text(NSLocalizedString("AUTH_AGREE_PRIVACY", comment: ""))
                                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                                    .underline()
                            }
                        }
                    }
                    .font(.footnote)
                }

                Spacer(minLength: 0)

                Button(action: {
                    dismiss()
                    onAccepted()
                }) {
                    Text(L10n.t("COMMON_CONTINUE"))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(hasAccepted ? ArboreDesign.Colors.primaryButton : ArboreDesign.Colors.primaryButton.opacity(0.4))
                        .cornerRadius(ArboreDesign.Radius.button)
                }
                .disabled(!hasAccepted)

                Button(action: { dismiss() }) {
                    Text(L10n.t("COMMON_BACK"))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(ArboreDesign.Colors.background)
        }
        .presentationDetents([.medium, .large])
    }
}
