import SwiftUI

struct SoilStepView: View {
    @ObservedObject var state: GardenWizardState
    let onNext: () -> Void
    let onBack: () -> Void
    
    var body: some View {
        ZStack {
            Color.gardenBackground
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quel est le type de sol ?")
                        .font(.system(size: 26, weight: .bold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(SoilType.allCases) { soil in
                            ImprovedSelectableCard(
                                isSelected: state.soil == soil,
                                systemImage: soil.iconName,
                                title: soil.title
                            ) {
                                state.soil = soil
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 15)
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button("Continuer") { onNext() }
                        .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.soil != nil))
                        .disabled(state.soil == nil)
                    
                    Button("Retour") { onBack() }
                        .buttonStyle(SecondaryWizardButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}
