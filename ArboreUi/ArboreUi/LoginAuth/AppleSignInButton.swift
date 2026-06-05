//
//  AppleSignInButton.swift
//  ArboreUi
//
//  Bouton « Sign in with Apple » NATIF (`SignInWithAppleButton`), conforme aux
//  Human Interface Guidelines d'Apple : logo officiel, police San Francisco,
//  libellé + localisation fournis par Apple, styles approuvés, proportions
//  normées. Remplace les boutons custom à base du SF Symbol `apple.logo`
//  (interdit hors bouton officiel par la licence SF Symbols / le trademark
//  Apple) qui exposaient à un rejet App Store (Guideline 4.8 + design SIWA).
//
//  Câble la logique existante d'`AppleAuthService` (nonce + échange Firebase +
//  forward de l'authorization_code pour la révocation #210) via
//  `configureRequest` / `handleAuthorization` / `handleError`.
//

import SwiftUI
import AuthenticationServices

struct AppleSignInButton: View {
    @ObservedObject var appleAuth: AppleAuthService
    @Environment(\.colorScheme) private var colorScheme

    /// Libellé Apple (localisé automatiquement). `.continue` = « Continuer avec
    /// Apple » / « Continue with Apple », cohérent avec l'ancien texte.
    var label: SignInWithAppleButton.Label = .continue
    var height: CGFloat = 50
    /// Style explicite. Si nil : choisi selon le `colorScheme` (blanc en dark,
    /// noir en light). À forcer sur un écran au fond non-adaptatif (ex. ReAuth,
    /// fond clair fixe → `.black`).
    var style: SignInWithAppleButton.Style?

    private var resolvedStyle: SignInWithAppleButton.Style {
        style ?? (colorScheme == .dark ? .white : .black)
    }

    var body: some View {
        SignInWithAppleButton(label) { request in
            appleAuth.configureRequest(request)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                appleAuth.handleAuthorization(authorization)
            case .failure(let error):
                appleAuth.handleError(error)
            }
        }
        .signInWithAppleButtonStyle(resolvedStyle)
        .frame(height: height)
        .cornerRadius(ArboreDesign.Radius.button)
    }
}
