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
                    Text(L10n.t("WIZARD_SPACE_TITLE"))
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
                                systemImage: spaceType.iconName,
                                title: spaceType.title,
                                subtitle: spaceType.subtitle
                            ) {
                                state.spaceType = spaceType
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 15)
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button(action: onNext) {
                        HStack {
                            Text(L10n.t("COMMON_CONTINUE"))
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.spaceType != nil))
                    .disabled(state.spaceType == nil)
                    
                    Button(L10n.t("COMMON_BACK")) { onBack() }
                        .buttonStyle(SecondaryWizardButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}
