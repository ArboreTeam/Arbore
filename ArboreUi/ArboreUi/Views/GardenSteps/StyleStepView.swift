import SwiftUI

struct StyleStepView: View {
    @ObservedObject var state: GardenWizardState
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
                            StyleCard(
                                style: style,
                                isSelected: state.style == style
                            ) {
                                state.style = style
                            }
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
