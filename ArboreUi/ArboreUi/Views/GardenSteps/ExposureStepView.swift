import SwiftUI

struct ExposureStepView: View {
    @ObservedObject var state: GardenWizardState
    let onNext: () -> Void
    let onBack: () -> Void
    
    var body: some View {
        ZStack {
            Color.gardenBackground
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quelle est l'exposition de votre espace ?")
                        .font(.system(size: 26, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text("Une estimation suffit.")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(SunExposure.allCases) { exposure in
                            ImprovedSelectableCard(
                                isSelected: state.exposure == exposure,
                                emoji: exposure.emoji,
                                title: exposure.title,
                                subtitle: exposure.subtitle
                            ) {
                                state.exposure = exposure
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button(action: onNext) {
                        HStack {
                            Text("Continuer")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.exposure != nil))
                    .disabled(state.exposure == nil)
                    
                    Button("Retour") { onBack() }
                        .buttonStyle(SecondaryWizardButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}