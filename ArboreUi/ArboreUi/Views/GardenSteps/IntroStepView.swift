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
                    Text("🌱")
                        .font(.system(size: 100))
                        .padding(.bottom, 8)
                    
                    Text("Construisons ensemble\nvotre futur jardin")
                        .font(.system(size: 32, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    
                    Text("Répondez à quelques questions pour\npersonnaliser votre espace avec nos\nconseils d'experts.")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                }
                
                Spacer()
                
                Button("Commencer") { onNext() }
                    .buttonStyle(PrimaryWizardButtonStyle(isEnabled: true))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }
}
