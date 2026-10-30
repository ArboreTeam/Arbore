import SwiftUI

struct StyleStepView: View {
    @ObservedObject var state: GardenWizardState
    // Observe la config distante pour le gating premium des styles (#236).
    // En bêta `membership.enforced == false` → aucun style n'est verrouillé.
    @ObservedObject private var remoteConfig = RemoteConfigService.shared
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        WizardStepScaffold {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("WIZARD_STYLE_TITLE"))
                        .font(.system(size: 28, weight: .bold))

                    Text(L10n.t("WIZARD_STYLE_SUBTITLE"))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(GardenStyle.allCases) { style in
                        let isLocked = remoteConfig.isStyleLocked(forKey: style.key)
                        StyleCard(
                            style: style,
                            isSelected: state.styles.contains(style)
                        ) {
                            // Style verrouillé (premium, gating actif) : on ne
                            // sélectionne pas. Le paywall sera branché avec #4.
                            guard !isLocked else { return }
                            state.toggleStyle(style)
                        }
                        .overlay(alignment: .topTrailing) {
                            if isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(7)
                                    .background(Color.black.opacity(0.45), in: Circle())
                                    .padding(10)
                            }
                        }
                        .opacity(isLocked ? 0.55 : 1)
                    }
                }
            }
            .padding(.horizontal, 24)
        } actions: {
            Button(action: onNext) {
                HStack {
                    Text(L10n.t("COMMON_CONTINUE"))
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryWizardButtonStyle(isEnabled: !state.styles.isEmpty))
            .disabled(state.styles.isEmpty)

            Button(L10n.t("COMMON_BACK")) { onBack() }
                .buttonStyle(SecondaryWizardButtonStyle())
        }
    }
}
