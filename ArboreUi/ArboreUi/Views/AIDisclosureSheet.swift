//
//  AIDisclosureSheet.swift
//  ArboreUi
//
//  Divulgation préalable au premier envoi vers le service d'IA — issue #607.
//

import SwiftUI

/// Feuille présentée **avant** que la moindre photo ou le moindre message ne
/// quitte l'appareil, et une seule fois par version de divulgation.
///
/// Elle existe parce qu'App Review a refusé la 1.0.0 (2) au titre de la
/// directive 5.1.1(i), qui impose quatre choses. La politique de confidentialité
/// en couvrait déjà trois, mais Apple écrit noir sur blanc que la politique ne
/// suffit pas : il faut le dire là où ça se passe, et demander. Cet écran reprend
/// donc les trois premières, dans l'ordre où Apple les énumère — quelles données,
/// à qui, pour quoi — et les deux boutons tiennent la quatrième.
///
/// Les deux réponses sont de vraies réponses. « Pas maintenant » n'est pas une
/// impasse : le scan se rabat sur la colorimétrie locale et l'assistant
/// s'annonce indisponible. C'est ce qui rend l'autorisation significative — une
/// demande dont le refus casse l'app n'est pas une demande.
struct AIDisclosureSheet: View {
    /// Appelé avec le choix de l'utilisateur. L'appelant enregistre la réponse
    /// puis reprend — ou non — l'action interrompue.
    let onDecision: (Bool) -> Void

    // Injecté à la racine (`ArboreUiApp`) et transmis explicitement à la
    // politique, comme le fait `PrivacySettingsView` : un `fullScreenCover` a
    // déjà perdu cet objet par le passé sur certaines versions d'iOS.
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPolicy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.lg) {
                entete
                points
                piedDePage
            }
            .padding(ArboreDesign.Spacing.lg)
            .padding(.bottom, ArboreDesign.Spacing.xxl)
        }
        .background(ArboreDesign.Colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { boutons }
        // Pas de fermeture par glissement : une divulgation qu'on peut écarter
        // sans répondre laisserait l'action d'origine dans les limbes, et
        // n'obtiendrait rien de ce que la directive demande.
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $showPolicy) {
            PrivacyPolicyView()
                .environmentObject(themeManager)
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.accentGold)

            Text(NSLocalizedString("AIDISCLOSURE_TITLE", comment: ""))
                .font(ArboreDesign.Typography.pageTitle)
                .foregroundColor(ArboreDesign.Colors.textPrimary)

            Text(NSLocalizedString("AIDISCLOSURE_SUBTITLE", comment: ""))
                .font(ArboreDesign.Typography.body)
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, ArboreDesign.Spacing.md)
    }

    // MARK: - Les trois points exigés, plus l'entraînement

    private var points: some View {
        VStack(spacing: ArboreDesign.Spacing.sm) {
            point(icone: "photo",
                  titre: "AIDISCLOSURE_WHAT_TITLE",
                  texte: "AIDISCLOSURE_WHAT_TEXT")
            point(icone: "arrow.up.forward.app",
                  titre: "AIDISCLOSURE_WHO_TITLE",
                  texte: "AIDISCLOSURE_WHO_TEXT")
            point(icone: "leaf",
                  titre: "AIDISCLOSURE_WHY_TITLE",
                  texte: "AIDISCLOSURE_WHY_TEXT")
            point(icone: "nosign",
                  titre: "AIDISCLOSURE_TRAINING_TITLE",
                  texte: "AIDISCLOSURE_TRAINING_TEXT")
        }
    }

    private func point(icone: String, titre: String, texte: String) -> some View {
        HStack(alignment: .top, spacing: ArboreDesign.Spacing.sm) {
            Image(systemName: icone)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xxs) {
                Text(NSLocalizedString(titre, comment: ""))
                    .font(ArboreDesign.Typography.cardTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                Text(NSLocalizedString(texte, comment: ""))
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(ArboreDesign.Spacing.cardPadding)
        .background(ArboreDesign.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }

    // MARK: - Pied de page

    private var piedDePage: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
            Text(NSLocalizedString("AIDISCLOSURE_DECLINE_NOTE", comment: ""))
                .font(ArboreDesign.Typography.bodySmall)
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(NSLocalizedString("AIDISCLOSURE_REVERSIBLE", comment: ""))
                .font(ArboreDesign.Typography.caption)
                .foregroundColor(ArboreDesign.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: { showPolicy = true }) {
                Text(NSLocalizedString("AIDISCLOSURE_READ_POLICY", comment: ""))
                    .font(ArboreDesign.Typography.bodySmall.weight(.semibold))
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Les deux réponses

    private var boutons: some View {
        VStack(spacing: ArboreDesign.Spacing.xs) {
            Button(action: { repondre(true) }) {
                Text(NSLocalizedString("AIDISCLOSURE_ACCEPT", comment: ""))
                    .font(ArboreDesign.Typography.button)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ArboreDesign.Spacing.md)
                    .background(ArboreDesign.Colors.primaryButton)
                    .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.button,
                                                style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: { repondre(false) }) {
                Text(NSLocalizedString("AIDISCLOSURE_DECLINE", comment: ""))
                    .font(ArboreDesign.Typography.button)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ArboreDesign.Spacing.sm)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, ArboreDesign.Spacing.lg)
        .padding(.top, ArboreDesign.Spacing.sm)
        .padding(.bottom, ArboreDesign.Spacing.xs)
        .background(ArboreDesign.Colors.background)
    }

    private func repondre(_ autorise: Bool) {
        AIProcessingPreference.enregistrerReponse(autorise: autorise)
        dismiss()
        onDecision(autorise)
    }
}
