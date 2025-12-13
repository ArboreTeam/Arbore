import SwiftUI

struct SpaceTypeStepView: View {
    @ObservedObject var state: GardenWizardState
    let onNext: () -> Void
    let onBack: () -> Void
    
    var body: some View {
        ZStack {
            Color.gardenBackground
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Où souhaitez-vous ajouter des plantes ?")
                        .font(.system(size: 26, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(GardenSpaceType.allCases) { spaceType in
                            ImprovedSelectableCard(
                                isSelected: state.spaceType == spaceType,
                                emoji: spaceType.emoji,
                                title: spaceType.title,
                                subtitle: spaceType.subtitle
                            ) {
                                state.spaceType = spaceType
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button(action: onNext) {
                        HStack {
                            Text("Continuer")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.spaceType != nil))
                    .disabled(state.spaceType == nil)
                    
                    Button("Retour") { onBack() }
                        .buttonStyle(SecondaryWizardButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}
