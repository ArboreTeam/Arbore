import SwiftUI

struct IntroStepView: View {
    let onNext: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Color.gardenBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 24) {
                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 92, weight: .semibold))
                        .foregroundColor(Color.gardenPrimary)
                        .padding(.bottom, 8)
                    
                    Text(L10n.t("WIZARD_INTRO_TITLE"))
                        .font(.system(size: 32, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    
                    Text(L10n.t("WIZARD_INTRO_SUBTITLE"))
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                }
                
                Spacer()
                
                Button(L10n.t("COMMON_START")) { onNext() }
                    .buttonStyle(PrimaryWizardButtonStyle(isEnabled: true))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }
}
