import SwiftUI

struct SpaceTypeStepView: View {
    @ObservedObject var state: GardenWizardState
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        WizardStepScaffold {
            VStack(alignment: .leading, spacing: 28) {
                Text(L10n.t("WIZARD_SPACE_TITLE"))
                    .font(.system(size: 26, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 16) {
                    ForEach(GardenSpaceType.allCases) { spaceType in
                        ImprovedSelectableCard(
                            isSelected: state.spaceType == spaceType,
                            icon: spaceType.iconName,
                            title: spaceType.title,
                            subtitle: spaceType.subtitle
                        ) {
                            state.spaceType = spaceType
                        }
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
            .buttonStyle(PrimaryWizardButtonStyle(isEnabled: state.spaceType != nil))
            .disabled(state.spaceType == nil)

            Button(L10n.t("COMMON_BACK")) { onBack() }
                .buttonStyle(SecondaryWizardButtonStyle())
        }
    }
}
