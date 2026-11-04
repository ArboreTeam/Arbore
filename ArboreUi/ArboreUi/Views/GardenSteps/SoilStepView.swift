import SwiftUI

struct SoilStepView: View {
    @ObservedObject var state: GardenWizardState
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        WizardStepScaffold {
            VStack(alignment: .leading, spacing: 28) {
                Text(L10n.t("WIZARD_SOIL_TITLE"))
                    .font(.system(size: 26, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 16) {
                    ForEach(SoilType.allCases) { soil in
                        ImprovedSelectableCard(
                            isSelected: state.soil == soil,
                            icon: soil.iconName,
                            title: soil.title
                        ) {
                            state.soil = soil
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        } actions: {
            Button(L10n.t("COMMON_CONTINUE")) { onNext() }
                .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.soil != nil))
                .disabled(state.soil == nil)

            Button(L10n.t("COMMON_BACK")) { onBack() }
                .buttonStyle(SecondaryWizardButtonStyle())
        }
    }
}
