import SwiftUI

struct StyleStepView: View {
    @ObservedObject var state: GardenWizardState
    // Observe la config distante pour le gating premium des styles (#236).
    // En bêta `membership.enforced == false` → aucun style n'est verrouillé.
    @ObservedObject private var remoteConfig = RemoteConfigService.shared
    let onNext: () -> Void
    let onBack: () -> Void
    
    var body: some View {
        ZStack {
            Color.gardenBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("WIZARD_STYLE_TITLE"))
                        .font(.system(size: 28, weight: .bold))
                    
                    Text(L10n.t("WIZARD_STYLE_SUBTITLE"))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
                
                // Grid of style cards
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(GardenStyle.allCases) { style in
                            let isLocked = remoteConfig.isStyleLocked(forKey: style.key)
                            StyleCard(
                                style: style,
                                isSelected: state.style == style
                            ) {
                                // Style verrouillé (premium, gating actif) : on ne
                                // sélectionne pas. Le paywall sera branché avec #4.
                                guard !isLocked else { return }
                                state.style = style
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
                    .padding(.horizontal, 24)
                    .padding(.bottom, 120) // un peu de marge pour ne pas coller aux boutons
                    .padding(.top, 15)
                }
            }
        }
        // Zone boutons collée au bottom, avec fond qui descend jusqu’en bas
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: onNext) {
                    HStack {
                        Text(L10n.t("COMMON_CONTINUE"))
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.style != nil))
                .disabled(state.style == nil)
                
                Button(L10n.t("COMMON_BACK")) { onBack() }
                    .buttonStyle(SecondaryWizardButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .background(
                LinearGradient(
                    colors: [
                        Color.gardenBackground.opacity(0),   // <--- remonte avec plus d’opacité
                        Color.gardenBackground.opacity(0.99),
                        Color.gardenBackground
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }
}
